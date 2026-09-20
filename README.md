# runtime-tools

Pinned Linux builds of MuPDF (`mutool`, with its bundled MuJS) and FFmpeg
(`ffmpeg`/`ffprobe`). AMD64 and ARM64 archives use the same source lock. Versions
change through reviewed commits; consumers never install a floating latest version.

## Build and verify

Requirements: Ruby 3.2+, Thor (`bundle install`), Docker, and Git. Docker must be
running. macOS development needs a Linux VM such as Colima. CI uses native Ubuntu
VM runners; local cross-architecture builds require Docker emulation.

```sh
bundle install
bundle exec ruby test/runtime_tools_test.rb
bin/runtime-tools build mupdf --arch arm64
bin/runtime-tools verify mupdf --arch arm64
bin/runtime-tools build ffmpeg --arch arm64
bin/runtime-tools verify ffmpeg --arch arm64
```

Use `--arch amd64` for the other architecture. Sources default to
`~/.cache/runtime-tools/sources`; outputs default to `dist/`. `--jobs` controls
compilation parallelism. Build containers fetch locked inputs first, then compile
with no network. Never bypass a failed checksum; inspect the upstream source and
review an explicit lock change.

Archives have one root: `<release-id>-linux-<arch>/`, containing `bin/`, licenses,
and build metadata. Runtime dependencies are glibc, libm, and (for FFmpeg) the
system C++/GCC runtime. Test targets: Ubuntu 24.04 and Debian 13, with baseline
x86-64 / ARMv8.0 CPU checks. Alpine/musl is unsupported.

FFmpeg retains native defaults and automatic dependency detection, plus common
external codecs including H.264, HEVC 8/10-bit, VP8/VP9, AV1, Opus, Vorbis, MP3,
WebP, subtitle/text rendering, and GnuTLS HTTPS input. Fonts are not bundled:
install Fontconfig configuration and a font package for text rendering, and provide
a writable user cache directory. HTTPS requires `ca-certificates` at
`/etc/ssl/certs/ca-certificates.crt`; certificate verification must succeed.

## Releases and updates

See [the release runbook](docs/releases.md). The workflow creates a **draft only**;
publishing remains a human step. CI artifacts are not published releases.
Corresponding source, license notices, checksums, provenance, and verification
reports accompany each release. Tool licenses apply independently; MuPDF is AGPL
and the selected FFmpeg configuration is GPL-enabled. Inspect the included license
files and fulfill their redistribution requirements before publishing binaries.

The [implementation plan](docs/plans/2026-09-20-pinned-runtime-tools.md) records the
accepted scope and deferred review decisions. Baseline/app integration is a later
change, after approved public artifacts exist.

See [validation and media coverage](docs/validation.md) for local evidence and
the outstanding native AMD64 checks.
