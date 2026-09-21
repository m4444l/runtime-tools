# runtime-tools

Pinned Linux builds of MuPDF (`mutool`, with its bundled MuJS) and FFmpeg
(`ffmpeg`/`ffprobe`). AMD64 and ARM64 archives use the same source lock. Versions
change through reviewed commits; consumers never install a floating latest version.

## Install precompiled tools

`install.rb` owns the release IDs, architecture checksums, verified extraction,
and smoke checks. It requires only Ruby standard libraries, curl, CA certificates,
and the system runtime libraries listed below. It never compiles sources or
downloads a floating latest release. No GitHub token is required.

For GitHub Actions, after setting up Ruby and runtime dependencies:

```yaml
- uses: m4444l/runtime-tools@main
```

The action installs into `$RUNNER_TEMP/runtime-tools` without sudo and adds its
`bin` directory to subsequent steps' PATH. For a local checkout, use
`bin/runtime-tools install --prefix /desired/path` (Thor required).

For containers, download `install.rb` from `main`, then run
`RUNTIME_TOOLS_PREFIX=/desired/path ruby install.rb`. Consumers follow explicit
installer/release-pin updates committed to main; upstream releases never update
the pins automatically. Consumers requiring an immutable installer can instead
use a fixed commit and verify the script's SHA256 before execution.
The standalone script does not require Thor or the rest of this repository.
Copy the whole installation prefix to preserve relative binary links, licenses,
and `share/runtime-tools/versions.json`. Published binary releases remain immutable.

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

**Check upstream releases** runs every Monday at 08:23 UTC and supports manual
dispatch. It compares stable MuPDF and FFmpeg source releases with
`config/lock.json`, writes a version table to the Actions summary, and fails when
a newer version is available. GitHub Actions notification preferences control
failure notifications. Fetch or parsing errors also fail the check. Run locally
with `ruby lib/runtime_tools/upstream_releases.rb`. Pins remain unchanged.

See [the release runbook](docs/releases.md). The release workflow creates a **draft only**;
publishing remains a human step. CI artifacts are not published releases.
Corresponding source, license notices, checksums, provenance, and verification
reports accompany each release. Tool licenses apply independently; MuPDF is AGPL
and the selected FFmpeg configuration is GPL-enabled. Inspect the included license
files and fulfill their redistribution requirements before publishing binaries.

Baseline uses this installer for containers and CI. Deferred review decisions
remain recorded in [the release runbook](docs/releases.md).

See [validation and media coverage](docs/validation.md) for local evidence and
native CI results.

## Shipping changes

Use the `ship-worktree` skill to land reviewed, tested changes directly on main.
Do not create pull requests or push worktree branches. CI runs after shipping;
release preparation still requires successful native validation. Shipping code
does not publish binary releases automatically.
