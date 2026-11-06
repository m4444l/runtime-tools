# frozen_string_literal: true
# Compares Arabic/Hebrew shaping (HarfBuzz via drawtext and libass) between two extracted FFmpeg archives.
# Usage (inside the fonts image): ruby shaping.rb BASELINE_ARCHIVE CANDIDATE_ARCHIVE
require_relative "smoke"
require "digest"

FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
TEXTS = { "arabic" => "مرحبا بالعالم العربية", "hebrew" => "שלום עולם עברית" }.freeze

def render(root, name, text)
  Dir.mktmpdir("shaping-") do |directory|
    File.binwrite("#{directory}/text.txt", text)
    File.write("#{directory}/sub.srt", "1\n00:00:00,000 --> 00:00:01,000\n#{text}\n")
    draw = "drawtext=fontfile=#{FONT}:textfile=#{directory}/text.txt:fontsize=40:fontcolor=white:x=20:y=30"
    pixels = Smoke.run("#{root}/bin/ffmpeg", "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "color=black:size=400x120:rate=1:duration=1", "-vf", draw, "-frames:v", "1", "-pix_fmt", "gray", "-f", "rawvideo", "-")
    ass = Smoke.run("#{root}/bin/ffmpeg", "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "color=black:size=400x120:rate=1:duration=1", "-vf", "subtitles=#{directory}/sub.srt:force_style='FontName=DejaVu Sans,FontSize=24'", "-frames:v", "1", "-pix_fmt", "gray", "-f", "rawvideo", "-")
    raise "#{name} drawtext rendered blank" if pixels.bytes.uniq.length < 2
    raise "#{name} libass rendered blank" if ass.bytes.uniq.length < 2
    [Digest::SHA256.hexdigest(pixels), Digest::SHA256.hexdigest(ass)]
  end
end

Dir.mktmpdir("shaping-roots-") do |directory|
  roots = ARGV.first(2).map.with_index do |archive, index|
    target = "#{directory}/#{index}"
    FileUtils.mkdir_p(target)
    Smoke.run("tar", "-xzf", archive, "-C", target)
    Dir["#{target}/*"].first
  end
  failed = false
  TEXTS.each do |name, text|
    baseline = render(roots[0], name, text)
    candidate = render(roots[1], name, text)
    # ZWNJ between letters breaks Arabic joining, so the output must differ when shaping works.
    broken = render(roots[1], name, text.chars.join("‌"))
    raise "#{name} joining control had no effect" if name == "arabic" && broken[0] == candidate[0]
    same = baseline[0] == candidate[0] && baseline[1] == candidate[1]
    failed ||= !same
    puts "#{same ? 'IDENTICAL' : 'DIFFERENT'} #{name} drawtext #{baseline[0][0, 12]} -> #{candidate[0][0, 12]}; libass #{baseline[1][0, 12]} -> #{candidate[1][0, 12]}"
  end
  exit(failed ? 1 : 0)
end
