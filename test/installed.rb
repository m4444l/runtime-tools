# frozen_string_literal: true
require "json"
require "open3"
require "tmpdir"

raise "Installer should not require root" if Process.uid.zero?
Dir.mktmpdir do |directory|
  script = File.join(directory, "regex.js")
  File.write(script, "new RegExp(Array(34).join('[a]')); print('MuJS regression passed');\n")
  raise "MuJS regression failed" unless system("mutool", "run", script)
  image = File.join(directory, "text.png")
  output, status = Open3.capture2e("ffmpeg", "-v", "error", "-f", "lavfi", "-i", "color=size=320x240:duration=0.1",
    "-vf", "drawtext=text=Runtime tools:fontcolor=white", "-frames:v", "1", "-update", "1", image)
  raise output unless status.success?
  output, status = Open3.capture2e("ffprobe", "-v", "error", "-show_entries", "stream=codec_name,width,height", "-of", "json", image)
  raise output unless status.success?
  stream = JSON.parse(output).fetch("streams").first
  raise "Unexpected preview" unless stream.values_at("codec_name", "width", "height") == ["png", 320, 240]
end
puts "PASS action PATH, non-root installation, MuJS, fonts, PNG preview, and ffprobe"
