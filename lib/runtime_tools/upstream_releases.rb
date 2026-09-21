# frozen_string_literal: true
require "json"
require "open3"
require "rubygems/version"

module RuntimeTools
  module UpstreamReleases
    SOURCES = {
      "mupdf" => ["https://mupdf.com/releases?product=MuPDF", %r(\bmupdf-(\d+(?:\.\d+)+)-source\.tar\.gz)],
      "ffmpeg" => ["https://ffmpeg.org/download.html", %r(\bffmpeg-(\d+(?:\.\d+)+)\.tar\.xz)]
    }.freeze

    def self.fetch(url)
      body, status = Open3.capture2("curl", "--fail", "--silent", "--show-error", "--location",
        "--proto", "=https", "--proto-redir", "=https", "--connect-timeout", "15",
        "--max-time", "60", "--retry", "2", url)
      raise "Could not fetch #{url}" unless status.success?
      body
    end

    def self.check(lock, fetcher: method(:fetch))
      lock.fetch("tools").map do |tool, spec|
        url, pattern = SOURCES.fetch(tool)
        versions = fetcher.call(url).scan(pattern).flatten
        raise "No stable source releases found at #{url}" if versions.empty?
        latest = versions.max_by { Gem::Version.new(_1) }
        current = spec.fetch("version")
        { tool:, current:, latest:, url:, newer: Gem::Version.new(latest) > Gem::Version.new(current) }
      end
    end

    def self.run
      lock = JSON.parse(File.read(File.expand_path("../../config/lock.json", __dir__)))
      results = check(lock)
      report = ["## Upstream releases", "", "| Tool | Pinned | Latest stable | Status |",
        "| --- | --- | --- | --- |"]
      results.each do |result|
        status = result.fetch(:newer) ? "Update available" : "No newer release"
        report << "| [#{result.fetch(:tool)}](#{result.fetch(:url)}) | #{result.fetch(:current)} | #{result.fetch(:latest)} | #{status} |"
      end
      report << "\nUpdates require a reviewed lock change and the release runbook."
      puts report.join("\n")
      if path = ENV["GITHUB_STEP_SUMMARY"]
        File.open(path, "a") { _1.puts report.join("\n") }
      end
      results.any? { _1.fetch(:newer) } ? 1 : 0
    end
  end
end

if $PROGRAM_NAME == __FILE__
  exit RuntimeTools::UpstreamReleases.run
end
