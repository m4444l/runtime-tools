# frozen_string_literal: true

require "minitest/autorun"
require "minitest/mock"
require_relative "../install"

class InstallerTest < Minitest::Test
  def subject_class = RuntimeTools::Installer

  def test_pins_both_supported_architectures_to_explicit_release_checksums
    subject_class::RELEASES.each do |name, spec|
      assert_match(/\A#{Regexp.escape(name)}-\d+\.\d+\.\d+-r\d+\z/, spec.fetch(:release))
      assert_equal %w[amd64 arm64], spec.fetch(:sha256).keys.sort
      spec.fetch(:sha256).each_value { assert_match(/\A[0-9a-f]{64}\z/, _1) }
    end
  end

  def test_rejects_changed_release_contents_before_extraction
    Dir.mktmpdir do |directory|
      destination = File.join(directory, "source")
      subject_class.stub :download, "changed archive" do
        assert_raises_with_message(RuntimeError, /Runtime tool checksum mismatch/) do
          subject_class.send(:extract, "https://example.com/source.tar.gz", destination, "package",
            Digest::SHA256.hexdigest("expected archive"))
        end
      end
      refute_path_exists destination
    end
  end

  def test_extracts_a_verified_release_archive
    Dir.mktmpdir do |directory|
      contents = archive_bytes([{ name: "package/VERSION", contents: "1.28.4" }])
      destination = File.join(directory, "extracted")
      subject_class.stub :download, contents do
        subject_class.send(:extract, "https://example.com/source.tar.gz", destination, "package",
          Digest::SHA256.hexdigest(contents))
      end
      assert_equal "1.28.4", File.read(File.join(destination, "package", "VERSION"))
    end
  end

  def test_aborts_failed_downloads_instead_of_falling_back_to_distribution_packages
    status = Struct.new(:success?).new(false)
    Open3.stub :capture3, ["", "HTTP 404", status] do
      assert_raises_with_message(RuntimeError, /Download failed.*HTTP 404/) do
        subject_class.send(:download, "https://example.com/missing.tar.gz")
      end
    end
  end

  def test_supports_long_names_while_rejecting_escaping_names_and_links
    long_name = "package/licenses/#{'long-directory/' * 10}COPYING"
    contents = archive_bytes([
      { name: "././@LongLink", contents: "#{long_name}\0", type: "L" },
      { name: "package/truncated", contents: "License notice" }
    ])
    Dir.mktmpdir do |directory|
      subject_class.stub :download, contents do
        subject_class.send(:extract, "https://example.com/archive", directory, "package", Digest::SHA256.hexdigest(contents))
      end
      assert_equal "License notice", File.read(File.join(directory, long_name))
      [
        [{ name: "package/../../escape", contents: "bad" }],
        [{ name: "/absolute", contents: "bad" }],
        [{ name: "other-root/file", contents: "bad" }],
        [{ name: "package/link", type: "2", linkname: "../../escape" }],
        [{ name: "package/link", type: "1", linkname: "../../escape" }],
        [{ name: "././@LongLink", contents: "package/../../escape\0", type: "L" }, { name: "package/truncated" }]
      ].each do |entries|
        invalid = archive_bytes(entries)
        subject_class.stub :download, invalid do
          assert_raises_with_message(RuntimeError, /Unsafe runtime tool archive entry/) do
            subject_class.send(:extract, "https://example.com/archive", directory, "package", Digest::SHA256.hexdigest(invalid))
          end
        end
      end
    end
  end

  def test_rejects_unsupported_platforms_before_downloading
    subject_class.stub :download, ->(*) { flunk "Unsupported platform must not download" } do
      %w[arm64-darwin x86_64-linux-musl riscv64-linux].each do |platform|
        assert_raises_with_message(RuntimeError, /Unsupported runtime tools/) do
          subject_class.install(prefix: "/unused", platform:)
        end
      end
    end
  end

  def test_installs_verified_public_archives_with_relocatable_binaries_and_license_metadata
    archives = {}
    releases = subject_class::RELEASES.to_h do |name, spec|
      root = "#{spec.fetch(:release)}-linux-amd64"
      metadata = JSON.generate(tool: name, release: spec.fetch(:release), architecture: "amd64")
      entries = spec.fetch(:binaries).map { { name: "#{root}/bin/#{_1}", contents: "synthetic executable", mode: 0o755 } }
      entries += [{ name: "#{root}/build-info.json", contents: metadata }, { name: "#{root}/licenses/COPYING", contents: "License notice" }]
      archives["#{root}.tar.gz"] = archive_bytes(entries)
      [name, spec.merge(sha256: { "amd64" => Digest::SHA256.hexdigest(archives.fetch("#{root}.tar.gz")) })]
    end
    subject_class.send(:remove_const, :RELEASES)
    subject_class.const_set(:RELEASES, releases)
    commands = []
    Dir.mktmpdir do |directory|
      prefix = File.join(directory, "install")
      subject_class.stub :download, ->(url) {
        assert_match(%r{\Ahttps://github.com/m4444l/runtime-tools/releases/download/}, url)
        refute_includes url, "/latest/"
        archives.fetch(File.basename(url))
      } do
        subject_class.stub :run, ->(*command) { commands << command } do
          selected = subject_class.install(prefix:, platform: "x86_64-linux")
          assert_equal releases.keys, selected.keys
        end
      end
      relocated = File.join(directory, "relocated")
      FileUtils.mv(prefix, relocated)
      releases.each_value do |spec|
        root = "#{spec.fetch(:release)}-linux-amd64"
        assert_path_exists File.join(relocated, "share/runtime-tools", root, "build-info.json")
        assert_equal "License notice", File.read(File.join(relocated, "share/runtime-tools", root, "licenses/COPYING"))
        spec.fetch(:binaries).each do |binary|
          path = File.join(relocated, "bin", binary)
          assert File.symlink?(path)
          assert File.executable?(path)
          assert_equal "synthetic executable", File.read(path)
        end
      end
      assert_equal %w[mutool mutool ffmpeg ffprobe], commands.map { File.basename(_1.first) }
      assert_equal "run", commands[1][1]
    end
  end

  def setup
    @original_releases = subject_class::RELEASES
  end

  def teardown
    subject_class.send(:remove_const, :RELEASES)
    subject_class.const_set(:RELEASES, @original_releases)
  end

  private

    def assert_raises_with_message(type, message, &block)
      error = assert_raises(type, &block)
      assert_match message, error.message
    end

    def archive_bytes(entries)
      tar = entries.map do |entry|
        contents = entry.fetch(:contents, "")
        header = Gem::Package::TarHeader.new(name: entry.fetch(:name), prefix: "", mode: entry.fetch(:mode, 0o644),
          size: contents.bytesize, typeflag: entry.fetch(:type, "0"), linkname: entry.fetch(:linkname, ""), mtime: 0)
        header.to_s + contents + "\0" * ((512 - contents.bytesize % 512) % 512)
      end.join + "\0" * 1024
      output = StringIO.new
      Zlib::GzipWriter.wrap(output) { _1.write(tar) }
      output.string
    end
end
