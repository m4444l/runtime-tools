# frozen_string_literal: true
module RuntimeTools
  class Verification
    def self.run(name, directory, arch)
      arch = RuntimeTools.architecture(arch)
      directory = File.expand_path(directory)
      root = "#{RuntimeTools.release(name)}-linux-#{arch}"
      archive = "#{directory}/#{root}.tar.gz"
      checksum = File.read("#{archive}.sha256").split.first
      RuntimeTools.verify(archive, checksum)
      RuntimeTools.lock.fetch("runtimes").each do |os, base|
        image = "runtime-tools-test:#{os}-#{arch}"
        RuntimeTools.run("docker", "build", "--platform", "linux/#{arch}", "--build-arg", "BASE_IMAGE=#{base}", "--build-arg", "SNAPSHOT=#{RuntimeTools.lock.fetch('builder').fetch('snapshot')}", "-f", "#{ROOT}/docker/runtime.Dockerfile", "-t", image, ROOT)
        mounts = ["-v", "#{ROOT}/test:/tests:ro", "-v", "#{directory}:/artifacts:ro"]
        RuntimeTools.run("docker", "run", "--rm", "--platform", "linux/#{arch}", "--network", "none", *mounts, image, "ruby", "/tests/extracted.rb", name, root)
        emulator = arch == "amd64" ? "qemu-x86_64 -cpu qemu64" : "qemu-aarch64 -cpu cortex-a53"
        RuntimeTools.run("docker", "run", "--rm", "--platform", "linux/#{arch}", "--network", "none", "-e", "CPU_EMULATOR=#{emulator}", *mounts, image, "ruby", "/tests/extracted.rb", name, root)
        next unless name == "ffmpeg"
        font_image = "#{image}-fonts"
        RuntimeTools.run("docker", "build", "--platform", "linux/#{arch}", "--build-arg", "BASE_IMAGE=#{image}", "-f", "#{ROOT}/docker/fonts.Dockerfile", "-t", font_image, ROOT)
        # --network none still permits loopback for the controlled HTTPS fixture.
        RuntimeTools.run("docker", "run", "--rm", "--platform", "linux/#{arch}", "--network", "none", "--user", "65534:65534", "-e", "HOME=/tmp", "-e", "XDG_CACHE_HOME=/tmp/runtime-tools-font-cache", "-e", "TEST_FONTS=1", *mounts, font_image, "ruby", "/tests/extracted.rb", name, root)
        RuntimeTools.run("docker", "run", "--rm", "--platform", "linux/#{arch}", "--network", "none", *mounts, image, "ruby", "/tests/https.rb", root)
        RuntimeTools.run("docker", "run", "--rm", "--platform", "linux/#{arch}", "--network", "none", "-e", "CPU_EMULATOR=#{emulator}", *mounts, image, "ruby", "/tests/https.rb", root)
      end
      report = { tool: name, architecture: arch, archive: File.basename(archive), sha256: checksum, runtimes: RuntimeTools.lock.fetch("runtimes"), cpu_baseline: true, fonts_and_https: name == "ffmpeg" }
      File.write("#{directory}/#{root}.verified.json", JSON.pretty_generate(report) + "\n")
    end
  end
end
