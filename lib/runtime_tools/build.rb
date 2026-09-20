# frozen_string_literal: true
module RuntimeTools
  class Build
    def initialize(name, options)
      @name, @options = name, options
      RuntimeTools.tool(name)
    end

    def run
      arch = RuntimeTools.architecture(@options[:arch])
      sources = Sources.new(@options[:sources])
      sources.fetch(@name)
      output = File.expand_path(@options[:output])
      FileUtils.mkdir_p(output)
      image = "runtime-tools-builder:#{arch}"
      builder = RuntimeTools.lock.fetch("builder")
      RuntimeTools.run("docker", "build", "--platform", "linux/#{arch}", "--build-arg", "BASE_IMAGE=#{builder.fetch('image')}", "--build-arg", "SNAPSHOT=#{builder.fetch('snapshot')}", "-f", File.join(ROOT, "docker/builder.Dockerfile"), "-t", image, ROOT)
      if File.file?("#{ROOT}/source-info.json")
        commit = JSON.parse(File.read("#{ROOT}/source-info.json")).fetch("build_commit")
        dirty = true # A source-bundle rebuild is not a clean release-workflow checkout.
      else
        commit = RuntimeTools.capture("git", "-C", ROOT, "rev-parse", "HEAD").strip
        dirty = !RuntimeTools.capture("git", "-C", ROOT, "status", "--porcelain").empty?
      end
      RuntimeTools.run("docker", "run", "--rm", "--platform", "linux/#{arch}", "--network", "none", "-v", "#{ROOT}:/repo:ro", "-v", "#{sources.directory}:/sources:ro", "-v", "#{output}:/output", "-e", "BUILD_COMMIT=#{commit}", "-e", "BUILD_DIRTY=#{dirty}", "-e", "BUILD_ARCH=#{arch}", image, "ruby", "/repo/bin/runtime-tools", "compile", @name, "--jobs", @options[:jobs].to_s)
    end
  end
end
