# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "rubygems/package"
require "stringio"
require "tmpdir"
require "zlib"

module RuntimeTools
  # Shared by CI and container builds; only Ruby standard libraries are needed.
  module Installer
    RELEASES = {
      "mupdf" => { release: "mupdf-1.28.4-r1", binaries: %w[mutool], sha256: {
        "amd64" => "9787e05d515595ab0a7395ed0d04f0089f2b7b3ed8c0572ce26b26128a7b1c54",
        "arm64" => "b145b8d4d2c116330871e463c661e77af6df72788552b18e88c12ed699c5849c"
      } },
      "ffmpeg" => { release: "ffmpeg-9.0.2-r1", binaries: %w[ffmpeg ffprobe], sha256: {
        "amd64" => "02f1f6a27f802c73cb5cac8ffeb162f3de16a3eccb318dd05d6c13936aaa6a9d",
        "arm64" => "b5a5814a5378ceb574eed3434ab7fda2277a557b63338cb06188d0ce1d90ffd1"
      } }
    }.freeze

    class << self
      def install(prefix:, platform: RUBY_PLATFORM)
        arch = architecture(platform)
        selected = RELEASES.to_h { |name, spec| [name, { release: spec.fetch(:release), sha256: spec.fetch(:sha256).fetch(arch) }] }
        Dir.mktmpdir("baseline-runtime-tools") do |directory|
          RELEASES.each do |name, spec|
            release = spec.fetch(:release)
            root = "#{release}-linux-#{arch}"
            url = "https://github.com/m4444l/runtime-tools/releases/download/#{release}/#{root}.tar.gz"
            extract(url, directory, root, selected.fetch(name).fetch(:sha256))
            metadata = JSON.parse(File.read(File.join(directory, root, "build-info.json")))
            unless metadata["tool"] == name && metadata["release"] == release && metadata["architecture"] == arch
              raise "Runtime tool metadata mismatch: #{root}"
            end
            raise "Missing runtime tool licenses: #{root}" if Dir.glob(File.join(directory, root, "licenses", "**", "*")).none? { File.file?(_1) }
            spec.fetch(:binaries).each do |binary|
              raise "Missing runtime executable: #{binary}" unless File.executable?(File.join(directory, root, "bin", binary))
            end
          end
          bin = File.join(prefix, "bin")
          share = File.join(prefix, "share", "runtime-tools")
          FileUtils.mkdir_p([bin, share])
          RELEASES.each_value do |spec|
            root = "#{spec.fetch(:release)}-linux-#{arch}"
            FileUtils.cp_r(File.join(directory, root), share)
            spec.fetch(:binaries).each do |binary|
              FileUtils.ln_sf("../share/runtime-tools/#{root}/bin/#{binary}", File.join(bin, binary))
            end
          end
          File.write(File.join(share, "versions.json"), JSON.pretty_generate(selected) + "\n")
          run(File.join(bin, "mutool"), "-v")
          smoke = File.join(directory, "smoke.js")
          File.write(smoke, "new RegExp(Array(34).join('[a]')); print('Bundled MuJS regex check passed');\n")
          run(File.join(bin, "mutool"), "run", smoke)
          run(File.join(bin, "ffmpeg"), "-version")
          run(File.join(bin, "ffprobe"), "-version")
        end
        selected
      end

      private

        def architecture(platform)
          unless platform.include?("linux") && !platform.include?("musl")
            raise "Unsupported runtime tools platform: #{platform}"
          end
          case platform.split("-").first
          when "x86_64", "amd64" then "amd64"
          when "aarch64", "arm64" then "arm64"
          else raise "Unsupported runtime tools architecture: #{platform}"
          end
        end

        def download(url)
          stdout, stderr, status = Open3.capture3("curl", "--fail", "--location", "--silent",
            "--show-error", "--proto", "=https", "--proto-redir", "=https", "--retry", "3",
            "--connect-timeout", "30", "--max-time", "300", url, binmode: true)
          raise "Download failed: #{url}: #{stderr}" unless status.success?

          stdout
        end

        def extract(url, destination, root, checksum)
          raise "Invalid runtime tool checksum" unless checksum.match?(/\A[0-9a-f]{64}\z/)
          contents = download(url)
          unless Digest::SHA256.hexdigest(contents) == checksum
            raise "Runtime tool checksum mismatch: #{url}"
          end
          Zlib::GzipReader.wrap(StringIO.new(contents)) do |gzip|
            Gem::Package::TarReader.new(gzip) do |tar|
              long_name = nil
              tar.each do |entry|
                if entry.header.typeflag == "L"
                  raise "Repeated GNU archive name" if long_name
                  long_name = entry.read.delete_suffix("\0")
                  next
                end
                name = long_name || entry.full_name
                long_name = nil
                parts = name.split("/")
                unless parts.first == root && !name.include?("\0") && (parts & ["..", ".", ""]).empty? && (entry.file? || entry.directory?)
                  raise "Unsafe runtime tool archive entry: #{name}"
                end
                path = File.join(destination, name)
                if entry.directory?
                  FileUtils.mkdir_p(path)
                else
                  FileUtils.mkdir_p(File.dirname(path))
                  File.binwrite(path, entry.read)
                  File.chmod(entry.header.mode & 0o755, path)
                end
              end
              raise "Dangling GNU archive name" if long_name
            end
          end
        end

        def run(*command)
          raise "Command failed: #{command.join(' ')}" unless system(*command)
        end
    end
  end
end

# Standalone bootstrap, deliberately independent of build-time gems and source checkout.
if $PROGRAM_NAME == __FILE__
  RuntimeTools::Installer.install(prefix: ENV.fetch("RUNTIME_TOOLS_PREFIX", "/usr/local"))
end
