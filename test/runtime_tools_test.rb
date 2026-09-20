# frozen_string_literal: true
require "minitest/autorun"
require "minitest/mock"
require_relative "../lib/runtime_tools"
require_relative "../lib/runtime_tools/release"

class RuntimeToolsTest < Minitest::Test
  def test_rejects_unknown_platform_before_building
    assert_raises(RuntimeTools::Error) { RuntimeTools.architecture("riscv64") }
    assert_equal "arm64", RuntimeTools.architecture("aarch64")
  end

  def test_source_checksum_is_checked_before_extraction
    Dir.mktmpdir do |directory|
      source = RuntimeTools.lock.fetch("sources").fetch("mupdf")
      File.write(File.join(directory, source.fetch("file")), "tampered")
      target = File.join(directory, "extracted")
      assert_raises(RuntimeTools::Error) { RuntimeTools::Sources.new(directory).extract("mupdf", target) }
      refute File.exist?(target)
    end
  end

  def test_lock_is_complete_and_no_sources_float
    lock = RuntimeTools.lock
    assert_match(/@sha256:[0-9a-f]{64}\z/, lock.fetch("builder").fetch("image"))
    lock.fetch("tools").each_key do |tool|
      RuntimeTools.source_specs(tool).each_value do |source|
        assert_match(/\A[0-9a-f]{64}\z/, source.fetch("sha256"))
        if source["git"]
          assert_match(/\A[0-9a-f]{40}\z/, source.fetch("commit"))
        else
          assert_match(%r(\Ahttps://), source.fetch("url"))
        end
      end
    end
  end

  def test_release_assembly_rejects_tampered_verified_artifact
    Dir.mktmpdir do |directory|
      root = "#{RuntimeTools.release('mupdf')}-linux-amd64"
      File.write("#{directory}/#{root}.tar.gz", "changed after verification")
      File.write("#{directory}/#{root}.verified.json", JSON.generate(tool: "mupdf", architecture: "amd64", runtimes: RuntimeTools.lock.fetch("runtimes"), cpu_baseline: true, sha256: "0" * 64))
      error = assert_raises(RuntimeTools::Error) { RuntimeTools::Release.prepare("mupdf", directory) }
      assert_match(/Checksum mismatch/, error.message)
      refute File.exist?("#{directory}/SHA256SUMS")
    end
  end

  def test_release_assembly_requires_both_architectures
    Dir.mktmpdir do |directory|
      assert_raises(Errno::ENOENT) { RuntimeTools::Release.prepare("mupdf", directory) }
      refute File.exist?("#{directory}/SHA256SUMS")
    end
  end

  def test_release_rejects_a_verified_build_from_uncommitted_changes
    Dir.mktmpdir do |directory|
      root = "#{RuntimeTools.release('mupdf')}-linux-amd64"
      FileUtils.mkdir_p("#{directory}/#{root}")
      File.write("#{directory}/#{root}/build-info.json", JSON.generate(working_tree_dirty: true))
      archive = "#{directory}/#{root}.tar.gz"
      RuntimeTools.run("tar", "-czf", archive, "-C", directory, root)
      File.write("#{directory}/#{root}.verified.json", JSON.generate(tool: "mupdf", architecture: "amd64", runtimes: RuntimeTools.lock.fetch("runtimes"), cpu_baseline: true, sha256: Digest::SHA256.file(archive).hexdigest))
      error = assert_raises(RuntimeTools::Error) { RuntimeTools::Release.prepare("mupdf", directory) }
      assert_match(/Dirty working-tree artifact/, error.message)
      refute File.exist?("#{directory}/SHA256SUMS")
    end
  end

  def test_release_assembles_only_the_verified_archives_and_corresponding_source
    Dir.mktmpdir do |directory|
      lock = RuntimeTools.lock
      lock["sources"]["mupdf"] = { "file" => "fixture-source.tar", "sha256" => Digest::SHA256.hexdigest("synthetic source") }
      RuntimeTools.stub(:lock, lock) do
        release = RuntimeTools.release("mupdf")
        sha = ENV["GITHUB_SHA"] || RuntimeTools.capture("git", "-C", RuntimeTools::ROOT, "rev-parse", "HEAD").strip
        %w[amd64 arm64].each do |arch|
          root = "#{release}-linux-#{arch}"
          FileUtils.mkdir_p("#{directory}/#{root}")
          File.write("#{directory}/#{root}/build-info.json", JSON.generate(lock:, working_tree_dirty: false, build_commit: sha))
          archive = "#{directory}/#{root}.tar.gz"
          RuntimeTools.run("tar", "-czf", archive, "-C", directory, root)
          checksum = Digest::SHA256.file(archive).hexdigest
          File.write("#{directory}/#{root}.verified.json", JSON.generate(tool: "mupdf", architecture: arch, runtimes: lock.fetch("runtimes"), cpu_baseline: true, sha256: checksum))
          File.write("#{directory}/#{root}.reproducibility.json", JSON.generate(first_sha256: checksum, second_sha256: checksum, identical: true))
        end
        FileUtils.mkdir_p("#{directory}/#{release}-source")
        File.write("#{directory}/#{release}-source/fixture-source.tar", "synthetic source")
        RuntimeTools.run("tar", "-czf", "#{directory}/#{release}-source.tar.gz", "-C", directory, "#{release}-source")
        RuntimeTools::Release.prepare("mupdf", directory)
        sums = File.readlines("#{directory}/SHA256SUMS", chomp: true)
        assert_equal 7, sums.length
        sums.each do |line|
          digest, file = line.split
          assert_equal digest, Digest::SHA256.file("#{directory}/#{file}").hexdigest
        end
        assert_equal 8, File.readlines("#{directory}/release-assets.txt").length
      end
    end
  end
end
