# frozen_string_literal: true
module RuntimeTools
  class Compiler
    PREFIX = "/opt/runtime-tools"

    def initialize(name, jobs)
      @name, @jobs = name, Integer(jobs)
      raise Error, "jobs must be positive" unless @jobs.positive?
      @arch = RuntimeTools.architecture(ENV.fetch("BUILD_ARCH"))
      @sources = Sources.new("/sources")
      @paths = {}
    end

    def run
      ENV["SOURCE_DATE_EPOCH"] = "1789776000"
      ENV["CFLAGS"] = "-O2 -fPIC -ffile-prefix-map=/work=. -ffile-prefix-map=/repo=."
      ENV["CXXFLAGS"] = ENV.fetch("CFLAGS")
      ENV["CPPFLAGS"] = "-I#{PREFIX}/include"
      ENV["LDFLAGS"] = "-L#{PREFIX}/lib"
      ENV["PKG_CONFIG_PATH"] = "#{PREFIX}/lib/pkgconfig:#{PREFIX}/share/pkgconfig"
      ENV["PATH"] = "#{PREFIX}/bin:#{ENV.fetch('PATH')}"
      RuntimeTools.source_specs(@name).each_key do |key|
        @paths[key] = "/work/#{key}"
        @sources.extract(key, @paths.fetch(key))
      end
      if @name == "mupdf"
        in_source("mupdf") do
          command("make", "-j#{@jobs}", "build=release", "USE_SYSTEM_LIBS=no", "USE_SYSTEM_MUJS=no", "HAVE_X11=no", "HAVE_GLUT=no", "HAVE_CURL=no", "HAVE_LIBCRYPTO=no", "build/release/mutool")
          FileUtils.mkdir_p("#{PREFIX}/bin")
          FileUtils.cp("build/release/mutool", "#{PREFIX}/bin/")
        end
      else
        verify_ffmpeg_signature
        dependencies
        in_source("ffmpeg") do
          command("./configure", "--prefix=#{PREFIX}", "--datadir=/usr/local/share/ffmpeg", "--disable-shared", "--enable-static", "--enable-gpl", "--disable-doc", "--disable-ffplay", "--disable-debug", "--pkg-config-flags=--static", "--extra-cflags=#{ENV.fetch('CFLAGS')} -I#{PREFIX}/include", "--extra-ldflags=-L#{PREFIX}/lib", "--extra-libs=-lstdc++ -lm -lpthread", "--enable-libx264", "--enable-libx265", "--enable-libvpx", "--enable-libopus", "--enable-libmp3lame", "--enable-libdav1d", "--enable-libvorbis", "--enable-libwebp", "--enable-libsvtav1", "--enable-libfreetype", "--enable-libharfbuzz", "--enable-libass", "--enable-libfontconfig", "--enable-gnutls", "--enable-zlib")
          make_install
        end
      end
      package
    end

    private

      def command(*args) = RuntimeTools.run(*args)
      def in_source(name, &block) = Dir.chdir(@paths.fetch(name), &block)

      def make_install
        command("make", "-j#{@jobs}")
        command("make", "install")
      end

      def autotools(name, *flags)
        in_source(name) do
          command("./configure", "--prefix=#{PREFIX}", "--libdir=#{PREFIX}/lib", "--disable-shared", "--enable-static", *flags)
          make_install
        end
      end

      def cmake(name, *flags, source: ".", build: "_build", install: true)
        in_source(name) do
          command("cmake", "-S", source, "-B", build, "-G", "Ninja", "-DCMAKE_BUILD_TYPE=Release", "-DCMAKE_INSTALL_PREFIX=#{PREFIX}", "-DCMAKE_INSTALL_LIBDIR=lib", "-DCMAKE_PREFIX_PATH=#{PREFIX}", "-DBUILD_SHARED_LIBS=OFF", "-DCMAKE_POSITION_INDEPENDENT_CODE=ON", *flags)
          command("cmake", "--build", build, "-j", @jobs.to_s)
          if install
            command("cmake", "--install", build)
          end
        end
      end

      def meson(name, *flags)
        in_source(name) do
          command("python3", "/work/meson/meson.py", "setup", "_build", "--prefix=#{PREFIX}", "--libdir=lib", "--default-library=static", "--buildtype=release", "--wrap-mode=nofallback", *flags)
          command("ninja", "-C", "_build", "-j", @jobs.to_s)
          command("ninja", "-C", "_build", "install")
        end
      end

      def dependencies
        in_source("zlib") do
          command("./configure", "--prefix=#{PREFIX}", "--static")
          make_install
        end
        in_source("x264") do
          command("./configure", "--prefix=#{PREFIX}", "--enable-static", "--enable-pic", "--disable-cli", "--disable-opencl")
          make_install
        end
        cmake("x265", "-DHIGH_BIT_DEPTH=ON", "-DEXPORT_C_API=OFF", "-DENABLE_CLI=OFF", "-DENABLE_SHARED=OFF", "-DENABLE_ASSEMBLY=OFF", source: "source", build: "_10bit", install: false)
        in_source("x265") do
          FileUtils.cp("_10bit/libx265.a", "#{PREFIX}/lib/libx265_main10.a")
        end
        cmake("x265", "-DENABLE_CLI=OFF", "-DENABLE_SHARED=OFF", "-DENABLE_ASSEMBLY=OFF", "-DEXTRA_LIB=#{PREFIX}/lib/libx265_main10.a", "-DLINKED_10BIT=ON", source: "source")
        # Merge the private bit-depth implementation so static pkg-config linkage is complete.
        in_source("x265") do
          File.write("merge.mri", "CREATE #{PREFIX}/lib/libx265-combined.a\nADDLIB #{PREFIX}/lib/libx265.a\nADDLIB #{PREFIX}/lib/libx265_main10.a\nSAVE\nEND\n")
          File.open("merge.mri") { RuntimeTools.run("ar", "-M", in: _1) }
          FileUtils.mv("#{PREFIX}/lib/libx265-combined.a", "#{PREFIX}/lib/libx265.a")
        end
        in_source("vpx") do
          target = @arch == "amd64" ? "x86_64-linux-gcc" : "arm64-linux-gcc"
          command("./configure", "--prefix=#{PREFIX}", "--target=#{target}", "--enable-pic", "--enable-runtime-cpu-detect", "--disable-examples", "--disable-tools", "--disable-docs", "--disable-unit-tests", "--disable-shared")
          make_install
        end
        autotools("opus", "--disable-doc", "--disable-extra-programs")
        autotools("lame", "--disable-frontend")
        meson("dav1d", "-Denable_tools=false", "-Denable_tests=false")
        autotools("ogg")
        autotools("vorbis", "--disable-docs", "--disable-examples")
        cmake("webp", "-DWEBP_BUILD_ANIM_UTILS=OFF", "-DWEBP_BUILD_CWEBP=OFF", "-DWEBP_BUILD_DWEBP=OFF", "-DWEBP_BUILD_GIF2WEBP=OFF", "-DWEBP_BUILD_IMG2WEBP=OFF", "-DWEBP_BUILD_VWEBP=OFF", "-DWEBP_BUILD_WEBPINFO=OFF", "-DWEBP_BUILD_WEBPMUX=OFF", "-DWEBP_BUILD_EXTRAS=OFF")
        cmake("svt_av1", "-DBUILD_APPS=OFF", "-DBUILD_TESTING=OFF")
        autotools("freetype", "--without-harfbuzz", "--without-bzip2", "--without-png", "--without-brotli")
        meson("harfbuzz", "-Dtests=disabled", "-Ddocs=disabled", "-Dutilities=disabled", "-Dglib=disabled", "-Dgobject=disabled", "-Dcairo=disabled", "-Dicu=disabled", "-Dfreetype=enabled")
        meson("fribidi", "-Ddocs=false", "-Dtests=false", "-Dbin=false")
        cmake("expat", "-DEXPAT_BUILD_TOOLS=OFF", "-DEXPAT_BUILD_EXAMPLES=OFF", "-DEXPAT_BUILD_TESTS=OFF", "-DEXPAT_SHARED_LIBS=OFF")
        meson("fontconfig", "--sysconfdir=/etc", "--localstatedir=/var", "-Ddefault-fonts-dirs=/usr/share/fonts", "-Dtemplate-dir=/usr/share/fontconfig/conf.avail", "-Dxml-dir=/usr/share/xml/fontconfig", "-Ddoc=disabled", "-Dtests=disabled", "-Dtools=disabled", "-Dcache-dir=/var/cache/fontconfig")
        autotools("ass", "--disable-test", "--disable-profile")
        triplet = @arch == "amd64" ? "x86_64-pc-linux-gnu" : "aarch64-unknown-linux-gnu"
        autotools("gmp", "--build=#{triplet}", "--host=#{triplet}", "--enable-fat", "--with-pic")
        autotools("nettle", "--enable-fat", "--disable-documentation", "--disable-openssl", "CCPIC=-fPIC")
        autotools("unistring")
        autotools("tasn1", "--disable-doc", "--disable-tools")
        autotools("gnutls", "--disable-doc", "--disable-tools", "--disable-tests", "--disable-cxx", "--without-p11-kit", "--without-tpm", "--without-tpm2", "--disable-guile", "--with-included-unistring=no", "--with-default-trust-store-file=/etc/ssl/certs/ca-certificates.crt", "--with-system-priority-file=/etc/gnutls/config", "--localedir=/usr/share/locale", "--datadir=/usr/share")
      end

      def verify_ffmpeg_signature
        FileUtils.mkdir_p("/work/gnupg", mode: 0o700)
        command("gpg", "--homedir", "/work/gnupg", "--import", "#{ROOT}/config/ffmpeg-release-key.asc")
        keys = RuntimeTools.capture("gpg", "--homedir", "/work/gnupg", "--with-colons", "--fingerprint")
        raise Error, "Unexpected FFmpeg signing key" unless keys.include?("FCF986EA15E6E293A5644F10B4322F04D67658D8")
        source = RuntimeTools.lock.fetch("sources").fetch("ffmpeg")
        command("gpg", "--homedir", "/work/gnupg", "--verify", "#{ROOT}/config/ffmpeg-#{source.fetch('version')}.tar.xz.asc", "/sources/#{source.fetch('file')}")
      end

      def package
        release = RuntimeTools.release(@name)
        root_name = "#{release}-linux-#{@arch}"
        staging = "/work/package/#{root_name}"
        FileUtils.mkdir_p(["#{staging}/bin", "#{staging}/licenses", "/output"])
        spec = RuntimeTools.tool(@name)
        needed = {}
        spec.fetch("binaries").each do |binary|
          FileUtils.cp("#{PREFIX}/bin/#{binary}", "#{staging}/bin/")
          elf = RuntimeTools.capture("readelf", "-d", "#{staging}/bin/#{binary}")
          headers = RuntimeTools.capture("readelf", "-h", "-l", "#{staging}/bin/#{binary}")
          machine, interpreter = if @arch == "amd64"
            ["Advanced Micro Devices X86-64", "/lib64/ld-linux-x86-64.so.2"]
          else
            ["AArch64", "/lib/ld-linux-aarch64.so.1"]
          end
          raise Error, "Wrong ELF architecture" unless headers.include?("Machine:                           #{machine}")
          raise Error, "Unexpected ELF interpreter" unless headers.include?("[Requesting program interpreter: #{interpreter}]")
          needed[binary] = elf.scan(/Shared library: \[(.*?)\]/).flatten
          allowed = %w[libc.so.6 libm.so.6 libmvec.so.1 libpthread.so.0 libdl.so.2 librt.so.1 libstdc++.so.6 libgcc_s.so.1 ld-linux-aarch64.so.1 ld-linux-x86-64.so.2]
          raise Error, "Unexpected runtime libraries: #{needed[binary] - allowed}" unless (needed[binary] - allowed).empty?
          versions = RuntimeTools.capture("readelf", "--version-info", "#{staging}/bin/#{binary}")
          if versions.scan(/GLIBC_(\d+)\.(\d+)/).any? { |major, minor| [major.to_i, minor.to_i].pack("NN") > [2, 39].pack("NN") }
            raise Error, "Binary requires glibc newer than Ubuntu 24.04"
          end
          raise Error, "Staging runtime loader path" if elf.match?(/(?:RPATH|RUNPATH).*\/(?:work|opt\/runtime-tools)/)
          strings = RuntimeTools.capture("strings", "#{staging}/bin/#{binary}")
          # The full configure command is informational; runtime config/data lookups aren't.
          runtime_paths = strings.lines.reject { _1.include?("--prefix=") || _1.include?("ffile-prefix-map=") }
          bad = runtime_paths.grep(%r{/(?:work|repo)/|/opt/runtime-tools/(?:etc|share|var)/})
          raise Error, "Embedded build/data paths: #{bad.first(5)}" unless bad.empty?
        end
        RuntimeTools.source_specs(@name).each do |key, source|
          destination = "#{staging}/licenses/#{key}"
          FileUtils.mkdir_p(destination)
          files = Dir.glob("#{@paths.fetch(key)}/**/{COPYING*,copying*,LICENSE*,license*,LICENCE*,licence*,Copyright*,copyright*,NOTICE*,notice*,README*,OFL.txt}").select { File.file?(_1) }
          raise Error, "Missing license for #{key}" if files.empty?
          files.each do |file|
            relative = Pathname.new(file).relative_path_from(Pathname.new(@paths.fetch(key))).to_s
            FileUtils.mkdir_p(File.dirname("#{destination}/#{relative}"))
            FileUtils.cp(file, "#{destination}/#{relative}")
          end
        end
        metadata = { tool: @name, release:, architecture: @arch, build_commit: ENV.fetch("BUILD_COMMIT"), lock: RuntimeTools.lock, runtime_libraries: needed, compiler: RuntimeTools.capture("cc", "--version"), packages: File.read("/usr/local/share/builder-packages.txt") }
        metadata[:working_tree_dirty] = ENV.fetch("BUILD_DIRTY", "true") != "false"
        if spec["mujs_commit"]
          metadata[:mujs_commit] = spec["mujs_commit"]
        end
        if @name == "ffmpeg"
          %w[buildconf codecs formats filters encoders decoders protocols].each do |feature|
            metadata[feature] = RuntimeTools.capture("#{staging}/bin/ffmpeg", "-hide_banner", "-#{feature}")
          end
        end
        File.write("#{staging}/build-info.json", JSON.pretty_generate(metadata) + "\n")
        archive = "/output/#{root_name}.tar.gz"
        command("tar", "--sort=name", "--mtime=@#{ENV.fetch('SOURCE_DATE_EPOCH')}", "--owner=0", "--group=0", "--numeric-owner", "-czf", archive, "-C", File.dirname(staging), root_name)
        File.write("#{archive}.sha256", "#{Digest::SHA256.file(archive).hexdigest}  #{File.basename(archive)}\n")
        sources_root = "/work/corresponding-source/#{release}-source"
        FileUtils.mkdir_p(sources_root)
        RuntimeTools.source_specs(@name).each_value { FileUtils.cp("/sources/#{_1.fetch('file')}", sources_root) }
        %w[lib bin docker config test .github .dockerignore .gitignore Gemfile Gemfile.lock README.md docs].each do |path|
          FileUtils.cp_r("#{ROOT}/#{path}", sources_root)
        end
        File.write("#{sources_root}/source-info.json", JSON.pretty_generate(build_commit: ENV.fetch("BUILD_COMMIT"), tool: @name) + "\n")
        command("tar", "--sort=name", "--mtime=@#{ENV.fetch('SOURCE_DATE_EPOCH')}", "--owner=0", "--group=0", "--numeric-owner", "-czf", "/output/#{release}-source.tar.gz", "-C", File.dirname(sources_root), File.basename(sources_root))
      end
  end
end
