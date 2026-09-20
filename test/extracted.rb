# frozen_string_literal: true
require_relative "smoke"
name, root = ARGV
raise "Invalid root" unless root&.match?(/\A(?:mupdf|ffmpeg)-[0-9.]+-r\d+-linux-(?:amd64|arm64)\z/)
Dir.mktmpdir("extracted-") do |directory|
  Smoke.run("tar", "-xzf", "/artifacts/#{root}.tar.gz", "-C", directory)
  Smoke.check(name, "#{directory}/#{root}")
end
