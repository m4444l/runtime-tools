# frozen_string_literal: true
require "digest"
require "fileutils"
require "json"
require "open3"
require "pathname"
require "tmpdir"

module RuntimeTools
  ROOT = File.expand_path("..", __dir__)
  Error = Class.new(StandardError)

  def self.run(*command, **options)
    puts "+ #{command.join(' ')}"
    raise Error, "Command failed: #{command.first}" unless system(*command, **options)
  end

  def self.capture(*command, **options)
    output, status = Open3.capture2e(*command, **options)
    raise Error, output unless status.success?
    output
  end

  def self.lock = JSON.parse(File.read(File.join(ROOT, "config/lock.json")))

  def self.default_sources
    return ROOT if File.file?("#{ROOT}/source-info.json")
    File.expand_path("~/.cache/runtime-tools/sources")
  end

  def self.tool(name)
    lock.fetch("tools").fetch(name) { raise Error, "Unknown tool: #{name}" }
  end

  def self.release(name)
    spec = tool(name)
    "#{name}-#{spec.fetch('version')}-r#{spec.fetch('revision')}"
  end

  def self.architecture(value)
    case value
    when "amd64", "x86_64" then "amd64"
    when "arm64", "aarch64" then "arm64"
    else raise Error, "Unsupported architecture: #{value}"
    end
  end

  def self.verify(path, expected)
    raise Error, "Invalid SHA256" unless expected.match?(/\A[0-9a-f]{64}\z/)
    raise Error, "Checksum mismatch: #{path}" unless Digest::SHA256.file(path).hexdigest == expected
  end

  def self.source_specs(name)
    tool(name).fetch("sources").to_h { [_1, lock.fetch("sources").fetch(_1)] }
  end
end

require_relative "runtime_tools/sources"
require_relative "runtime_tools/build"
