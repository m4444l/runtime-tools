# frozen_string_literal: true
module RuntimeTools
  class Release
    def self.prepare(name, directory)
      release = RuntimeTools.release(name)
      directory = File.expand_path(directory)
      assets = []
      metadata_by_arch = {}
      %w[amd64 arm64].each do |arch|
        root = "#{release}-linux-#{arch}"
        archive = "#{directory}/#{root}.tar.gz"
        report = JSON.parse(File.read("#{directory}/#{root}.verified.json"))
        raise Error, "Verification report mismatch" unless report.fetch("tool") == name && report.fetch("architecture") == arch && report.fetch("runtimes") == RuntimeTools.lock.fetch("runtimes") && report.fetch("cpu_baseline")
        raise Error, "Missing font/TLS verification" if name == "ffmpeg" && !report.fetch("fonts_and_https")
        RuntimeTools.verify(archive, report.fetch("sha256"))
        metadata = JSON.parse(RuntimeTools.capture("tar", "-xOf", archive, "#{root}/build-info.json"))
        metadata_by_arch[arch] = metadata
        raise Error, "Dirty working-tree artifact cannot be released" unless metadata["working_tree_dirty"] == false
        raise Error, "Build lock differs from release lock" unless metadata.fetch("lock") == RuntimeTools.lock
        expected_sha = ENV["GITHUB_SHA"] || RuntimeTools.capture("git", "-C", ROOT, "rev-parse", "HEAD").strip
        raise Error, "Build commit differs from release commit" unless metadata.fetch("build_commit") == expected_sha
        assets.concat([archive, "#{directory}/#{root}.verified.json"])
        comparison = "#{directory}/#{root}.reproducibility.json"
        repeat_report = JSON.parse(File.read(comparison))
        first, second = repeat_report.values_at("first_sha256", "second_sha256")
        valid_hashes = [first, second].all? { _1.is_a?(String) && _1.match?(/\A[0-9a-f]{64}\z/) }
        unless valid_hashes && repeat_report["tool"] == name && repeat_report["architecture"] == arch &&
            first == report.fetch("sha256") && repeat_report["identical"] == (first == second)
          raise Error, "Wrong repeat-build report"
        end
        assets << comparison
      end
      if name == "ffmpeg"
        differences = %w[codecs formats filters encoders decoders protocols].to_h do |feature|
          amd64, arm64 = %w[amd64 arm64].map { metadata_by_arch.fetch(_1).fetch(feature).lines.map(&:strip) }
          [feature, { amd64_only: amd64 - arm64, arm64_only: arm64 - amd64 }]
        end
        path = "#{directory}/#{release}-feature-comparison.json"
        File.write(path, JSON.pretty_generate(differences) + "\n")
        assets << path
      end
      source = "#{directory}/#{release}-source.tar.gz"
      raise Error, "Missing corresponding source" unless File.file?(source)
      entries = RuntimeTools.capture("tar", "-tf", source).lines.map(&:strip)
      RuntimeTools.source_specs(name).each_value do |spec|
        expected = "#{release}-source/#{spec.fetch('file')}"
        raise Error, "Missing source #{expected}" unless entries.include?(expected)
        digest = Digest::SHA256.new
        status = nil
        Open3.popen2("tar", "-xOf", source, expected) do |input, output, waiter|
          input.close
          while chunk = output.read(1024 * 1024)
            digest.update(chunk)
          end
          status = waiter.value
        end
        raise Error, "Incorrect source #{expected}" unless status.success? && digest.hexdigest == spec.fetch("sha256")
      end
      assets << source
      sums = assets.sort.map { "#{Digest::SHA256.file(_1).hexdigest}  #{File.basename(_1)}" }
      File.write("#{directory}/SHA256SUMS", sums.join("\n") + "\n")
      File.write("#{directory}/release-assets.txt", (assets + ["#{directory}/SHA256SUMS"]).join("\n") + "\n")
    end
  end
end
