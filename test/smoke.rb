# frozen_string_literal: true
require "json"
require "open3"
require "fileutils"
require "tmpdir"

module Smoke
  def self.run(*args)
    output, error, status = Open3.capture3(*args)
    raise "#{args.join(' ')}\n#{error}" unless status.success?
    output
  end

  def self.pdf(path)
    content = "BT /F1 16 Tf 30 150 Td (REMOVE ME) Tj 0 -40 Td (KEEP TOTAL 123) Tj ET"
    xml = "<invoice>synthetic</invoice>"
    objects = [
      "<< /Type /Catalog /Pages 2 0 R /Names << /EmbeddedFiles << /Names [(invoice.xml) 6 0 R] >> >> >>",
      "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 200] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
      "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
      "<< /Length #{content.bytesize} >>\nstream\n#{content}\nendstream",
      "<< /Type /Filespec /F (invoice.xml) /EF << /F 7 0 R >> >>",
      "<< /Type /EmbeddedFile /Length #{xml.bytesize} >>\nstream\n#{xml}\nendstream"
    ]
    document = +"%PDF-1.7\n"
    offsets = [0]
    objects.each_with_index do |object, index|
      offsets << document.bytesize
      document << "#{index + 1} 0 obj\n#{object}\nendobj\n"
    end
    start = document.bytesize
    document << "xref\n0 #{offsets.length}\n0000000000 65535 f \n"
    offsets.drop(1).each { document << format("%010d 00000 n \n", _1) }
    document << "trailer\n<< /Size #{offsets.length} /Root 1 0 R >>\nstartxref\n#{start}\n%%EOF\n"
    File.binwrite(path, document)
  end

# Lossless RGB24 -> PNG -> RGB24 must reproduce every byte (exercises zlib deflate/inflate in FFmpeg's PNG codec).
def self.png_round_trip(command, common)
  pixels = Array.new(128 * 96 * 3) { |i| (i * 7 + i / 384 * 13) % 256 }.pack("C*")
  File.binwrite("rgb.raw", pixels)
  command.call("ffmpeg", *common, "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", "128x96", "-i", "rgb.raw", "-frames:v", "1", "roundtrip.png")
  raise "PNG round trip signature missing" unless File.binread("roundtrip.png", 8) == "\x89PNG\r\n\x1a\n".b
  command.call("ffmpeg", *common, "-i", "roundtrip.png", "-f", "rawvideo", "-pix_fmt", "rgb24", "roundtrip.raw")
  raise "PNG round trip changed pixels" unless File.binread("roundtrip.raw") == pixels
end

# FLV container with H.264/AAC plus Flash Screen Video, whose decoder inflates zlib data.
def self.flv_stream(command, common, rails)
  audio = %w[-f s16le -ar 48000 -ac 1 -i audio.s16]
  command.call("ffmpeg", *common, "-i", "input.y4m", *audio, "-c:v", "libx264", "-c:a", "aac", "-f", "flv", "stream.flv")
  info = JSON.parse(command.call("ffprobe", *rails.fetch("probe"), "stream.flv"))
  codecs = info.fetch("streams").map { _1["codec_name"] }.sort
  raise "Wrong FLV streams #{codecs}" unless codecs == %w[aac h264]
  command.call("ffmpeg", *common, "-i", "stream.flv", "-f", "null", "-")
  command.call("ffmpeg", *common, "-i", "input.y4m", "-c:v", "flashsv", "-f", "flv", "screen.flv")
  raise "Wrong Flash Screen Video codec" unless JSON.parse(command.call("ffprobe", *rails.fetch("probe"), "screen.flv")).fetch("streams").first["codec_name"] == "flashsv"
  command.call("ffmpeg", *common, "-i", "screen.flv", "-f", "null", "-")
  decoded = command.call("ffmpeg", *common, "-i", "screen.flv", "-pix_fmt", "bgr24", "-f", "rawvideo", "-").bytesize
  raise "Wrong Flash Screen Video frames" unless decoded == 128 * 96 * 3 * 10
end

# Loopback HTTP server answering with Content-Encoding: gzip; FFmpeg must request and inflate it.
def self.http_gzip_stream(command, common)
  require "socket"
  require "zlib"
  plain = File.binread("audio.s16")
  body = Zlib.gzip(plain)
  server = TCPServer.new("127.0.0.1", 0)
  port = server.addr[1]
  requests = []
  thread = Thread.new do
    loop do
      client = server.accept
      request = +""
      request << client.readpartial(4096) until request.include?("\r\n\r\n")
      requests << request
      gzip = request.match?(/^Accept-Encoding:.*gzip/i)
      payload = gzip ? body : plain
      headers = ["HTTP/1.1 200 OK", "Content-Type: audio/L16", "Content-Length: #{payload.bytesize}", "Connection: close"]
      headers << "Content-Encoding: gzip" if gzip
      client.write(headers.join("\r\n") + "\r\n\r\n" + payload)
      client.close
    end
  rescue IOError, EOFError, SystemCallError
    nil
  end
  begin
    url = "http://127.0.0.1:#{port}/audio.s16"
    output = command.call("ffmpeg", *common, "-headers", "Accept-Encoding: gzip\r\n", "-f", "s16le", "-ar", "48000", "-ac", "1", "-i", url, "-f", "s16le", "-")
    raise "HTTP gzip request lacked Accept-Encoding" unless requests.any? { _1.match?(/^Accept-Encoding:.*gzip/i) }
    raise "HTTP gzip stream changed samples" unless output.b == plain.b
  ensure
    thread.kill
    server.close
  end
end

# Preview of the committed fixture using the Rails flags; checks size and picture content.
def self.fixture_preview(command, common, rails)
  jpeg = command.call("ffmpeg", "-i", "#{__dir__}/fixtures/h264-aac.mp4", *rails.fetch("preview")).b
  raise "Invalid fixture preview" unless jpeg.start_with?("\xff\xd8".b)
  File.binwrite("fixture-preview.jpg", jpeg)
  command.call("ffmpeg", *common, "-i", "fixture-preview.jpg", "-frames:v", "1", "fixture-preview.png")
  raise "Wrong fixture preview dimensions" unless File.binread("fixture-preview.png")[16, 8].unpack("NN") == [128, 96]
  pixels = command.call("ffmpeg", *common, "-i", "fixture-preview.jpg", "-pix_fmt", "gray", "-f", "rawvideo", "-").bytes
  raise "Wrong fixture preview content" unless pixels.length == 128 * 96 && pixels.uniq.length > 16
end

# Stock Fontconfig (distro /etc/fonts, no overrides) must load without errors and resolve a family name.
def self.stock_fontconfig(wrapper, root)
  raise "Stock Fontconfig test must not override its configuration" if ENV.key?("FONTCONFIG_FILE") || ENV.key?("FONTCONFIG_PATH")
  _, error, status = Open3.capture3(*wrapper, "#{root}/bin/ffmpeg", "-hide_banner", "-loglevel", "info", "-y", "-i", "video.mp4", "-vf", "drawtext=text=Hello:font=DejaVu Sans", "-frames:v", "1", "fontconfig.png")
  raise "Stock Fontconfig drawtext failed\n#{error}" unless status.success?
  raise "Fontconfig reported errors\n#{error}" if error.match?(/fontconfig (error|warning)/i)
end

  def self.check(tool, root)
    expected_version = JSON.parse(File.read("#{root}/build-info.json")).fetch("lock").fetch("tools").fetch(tool).fetch("version")
    binaries = tool == "mupdf" ? %w[mutool] : %w[ffmpeg ffprobe]
    wrapper = ENV["CPU_EMULATOR"].to_s.split
    command = ->(binary, *args) { run(*wrapper, "#{root}/bin/#{binary}", *args) }
    binaries.each do |binary|
      output = run("ldd", "#{root}/bin/#{binary}")
      raise "Missing runtime library" if output.include?("not found")
    end
    Dir.mktmpdir("runtime-smoke-") do |directory|
      Dir.chdir(directory) do
        if tool == "mupdf"
          version, status = Open3.capture2e(*wrapper, "#{root}/bin/mutool", "-v")
          raise "Wrong mutool version" unless status.success? && version.include?(expected_version)
          pdf("input.pdf")
          command.call("mutool", "run", "#{__dir__}/fixtures/mupdf.js", "input.pdf", "output.pdf")
          command.call("mutool", "draw", "-q", "-F", "png", "-o", "page.png", "output.pdf", "1")
          raise "Invalid PDF preview" unless File.binread("page.png", 8) == "\x89PNG\r\n\x1a\n".b
          raise "Wrong PDF preview dimensions" unless File.binread("page.png")[16, 8].unpack("NN") == [300, 200]
        else
          raise "Wrong FFmpeg version" unless command.call("ffmpeg", "-version").include?(expected_version)
          # Independent raw video/audio inputs; no tested decoder creates these inputs.
          frame = ([96] * (128 * 96) + [128] * (128 * 96 / 2)).pack("C*")
          File.binwrite("input.y4m", "YUV4MPEG2 W128 H96 F10:1 Ip A1:1 C420jpeg\n" + ("FRAME\n" + frame) * 10)
          File.binwrite("audio.s16", Array.new(48_000) { (Math.sin(_1 * 440 * 2 * Math::PI / 48_000) * 8000).round }.pack("s<*"))
          common = %w[-hide_banner -loglevel error -y -threads 2]
          command.call("ffmpeg", *common, "-i", "#{__dir__}/fixtures/h264-aac.mp4", "-f", "null", "-")
          audio = %w[-f s16le -ar 48000 -ac 1 -i audio.s16]
          command.call("ffmpeg", *common, "-i", "input.y4m", *audio, "-c:v", "libx264", "-threads", "2", "-c:a", "aac", "video.mp4")
          rails = JSON.parse(File.read("#{__dir__}/fixtures/rails-8.1.json"))
          info = JSON.parse(command.call("ffprobe", *rails.fetch("probe"), "video.mp4"))
          video = info.fetch("streams").find { _1["codec_type"] == "video" }
          raise "Wrong metadata" unless video["width"] == 128 && video["height"] == 96 && (info["format"]["duration"].to_f - 1).abs < 0.2
          jpeg = command.call("ffmpeg", "-i", "video.mp4", *rails.fetch("preview")).b
          raise "Invalid Rails preview" unless jpeg.start_with?("\xff\xd8".b)
          File.binwrite("preview.jpg", jpeg)
          command.call("ffmpeg", *common, "-i", "preview.jpg", "-frames:v", "1", "preview.png")
          raise "PNG output missing" unless File.binread("preview.png", 8) == "\x89PNG\r\n\x1a\n".b
          raise "Wrong preview dimensions" unless File.binread("preview.png")[16, 8].unpack("NN") == [128, 96]
          png_round_trip(command, common)
          flv_stream(command, common, rails)
          http_gzip_stream(command, common)
          fixture_preview(command, common, rails)
          pixels = command.call("ffmpeg", *common, "-i", "preview.jpg", "-pix_fmt", "gray", "-f", "rawvideo", "-").bytes
          raise "Wrong preview content" unless pixels.length == 128 * 96 && pixels.sum.fdiv(pixels.length).between?(80, 110)
          command.call("ffmpeg", *common, "-i", "input.y4m", *audio, "-c:v", "libvpx-vp9", "-deadline", "realtime", "-cpu-used", "8", "-c:a", "libopus", "video.webm")
          command.call("ffmpeg", *common, "-i", "video.webm", "-f", "null", "-")
          %w[libvpx libvpx-vp9 libx265 libsvtav1].each do |encoder|
            extra = case encoder
            when "libx265" then %w[-x265-params pools=1:frame-threads=1]
            when "libsvtav1" then %w[-preset 12 -svtav1-params lp=2]
            else %w[-deadline realtime -cpu-used 8]
            end
            command.call("ffmpeg", *common, "-i", "input.y4m", "-c:v", encoder, "-threads", "2", *extra, "encoded.mkv")
            command.call("ffmpeg", *common, "-i", "encoded.mkv", "-f", "null", "-")
          end
          command.call("ffmpeg", *common, "-i", "input.y4m", "-pix_fmt", "yuv420p10le", "-c:v", "libx265", "-x265-params", "pools=1:frame-threads=1", "main10.mkv")
          main10 = JSON.parse(command.call("ffprobe", *rails.fetch("probe"), "main10.mkv"))
          raise "Missing Main10" unless main10.fetch("streams").first["pix_fmt"] == "yuv420p10le"
          command.call("ffmpeg", *common, "-i", "main10.mkv", "-f", "null", "-")
          %w[libopus libvorbis].each do |encoder|
            command.call("ffmpeg", *common, *audio, "-c:a", encoder, "audio.oga")
            command.call("ffmpeg", *common, "-i", "audio.oga", "-acodec", "libmp3lame", "audio.mp3")
            command.call("ffmpeg", *common, "-i", "audio.mp3", "audio.wav")
          end
          command.call("ffmpeg", *common, "-i", "input.y4m", "-frames:v", "1", "-c:v", "libwebp", "image.webp")
          command.call("ffmpeg", *common, "-i", "image.webp", "-f", "null", "-")
          command.call("ffmpeg", *common, "-display_rotation:v:0", "90", "-i", "video.mp4", "-c", "copy", "rotated.mov")
          rotation = JSON.parse(command.call("ffprobe", *rails.fetch("probe"), "rotated.mov"))
          raise "Rotation metadata missing" unless rotation.fetch("streams").any? { _1.fetch("side_data_list", []).any? { |data| data["rotation"].to_i.abs == 90 } }
          if ENV["TEST_FONTS"] == "1"
            File.write("caption.srt", "1\n00:00:00,000 --> 00:00:01,000\nSynthetic subtitle\n")
            command.call("ffmpeg", *common, "-i", "video.mp4", "-vf", "drawtext=text=Hello:fontcolor=white,subtitles=caption.srt", "-frames:v", "1", "text.png")
            command.call("ffmpeg", *common, "-i", "video.mp4", "-frames:v", "1", "plain.png")
            stock_fontconfig(wrapper, root)
            raise "Text rendering did not affect output" if File.binread("text.png") == File.binread("plain.png")
          else
            _, error, status = Open3.capture3(*wrapper, "#{root}/bin/ffmpeg", *common, "-i", "video.mp4", "-vf", "drawtext=text=Hello", "-frames:v", "1", "text.png")
            raise "Missing fonts were not diagnosed" unless !status.success? && error.match?(/font/i)
          end
        end
      end
    end
    puts "PASS #{tool} #{ENV.fetch('CPU_EMULATOR', 'native')}"
  end
end

Smoke.check(ARGV.fetch(0), ARGV.fetch(1)) if $PROGRAM_NAME == __FILE__
