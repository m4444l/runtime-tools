# frozen_string_literal: true
require_relative "smoke"
require "socket"
root = ARGV.fetch(0)
raise "Invalid root" unless root.match?(/\Affmpeg-[0-9.]+-r\d+-linux-(?:amd64|arm64)\z/)
Smoke.run("tar", "-xzf", "/artifacts/#{root}.tar.gz", "-C", "/test")
Dir.mktmpdir("https-") do |directory|
  Dir.chdir(directory) do
    pcm = [0].pack("s<") * 8000
    File.binwrite("input.wav", "RIFF" + [36 + pcm.bytesize].pack("V") + "WAVEfmt " + [16, 1, 1, 8000, 16000, 2, 16].pack("VvvVVvv") + "data" + [pcm.bytesize].pack("V") + pcm)
    Smoke.run("openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", "key.pem", "-out", "cert.pem", "-days", "1", "-subj", "/CN=localhost", "-addext", "subjectAltName=DNS:localhost", "-addext", "basicConstraints=critical,CA:TRUE")
    process = Process.spawn("openssl", "s_server", "-quiet", "-accept", "18443", "-key", "key.pem", "-cert", "cert.pem", "-WWW", out: "server.log", err: "server.log")
    begin
      ready = false
      50.times do
        begin
          TCPSocket.new("127.0.0.1", 18443).close
          ready = true
          break
        rescue Errno::ECONNREFUSED
          sleep 0.1
        end
      end
      raise "HTTPS fixture did not start" unless ready
      probe = [*ENV["CPU_EMULATOR"].to_s.split, "/test/#{root}/bin/ffprobe", "-v", "error", "-show_format", "https://localhost:18443/input.wav"]
      _, _, status = Open3.capture3(*probe)
      raise "Untrusted certificate accepted" if status.success?
      FileUtils.cp("cert.pem", "/usr/local/share/ca-certificates/runtime-tools-test.crt")
      Smoke.run("update-ca-certificates")
      Smoke.run(*probe)
      puts "PASS HTTPS system trust and untrusted certificate rejection"
    ensure
      Process.kill("TERM", process)
      Process.wait(process)
    end
  end
end
