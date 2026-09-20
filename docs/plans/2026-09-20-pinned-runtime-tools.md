# Pinned MuPDF and FFmpeg builds

## Goal and scope

Build public Linux binaries once per reviewed version in `m4444l/runtime-tools`.
Applications and CI download identical, checksum-pinned archives without private
repository tokens. Updates are explicit changes, never floating `latest` installs.

Compile MuPDF with a pinned embedded MuJS, and compile FFmpeg with ffprobe.
Earlier discussion considered mirroring third-party FFmpeg binaries; source builds
are the selected approach following the request to compile both tools. Do not add
both approaches initially. No standalone MuJS CLI is needed by applications.

Implementation authorized on 2026-09-21; see [validation](../validation.md) for
implementation evidence and remaining platform checks. Release publication,
consumer migration, deployment, and resolution of the original workflow problem
remain separate steps requiring their appropriate review. Poppler removal, Rails previewer changes,
libvips, and other runtime tools are outside this initial scope.

## Versions and source lock

Initial versions, checked against upstream on 2026-09-20:

| Component | Version | Source |
| --- | --- | --- |
| MuPDF / mutool | 1.28.4 | https://mupdf.com/releases/history |
| Embedded MuJS | MuPDF's bundled commit `e892c9fdbbddba94e52f656ccb378ed4885e30cc` | https://github.com/ArtifexSoftware/mupdf/tree/1.28.4/thirdparty/mujs |
| FFmpeg / ffprobe | 9.0.2 | https://ffmpeg.org/download.html |

Add a machine-readable lock manifest containing exact source URLs, versions,
SHA256 hashes, patches, external codec dependency versions, builder image digests,
and release revision. No branch tips, automatic dependency upgrades, or mutable
container tags as final build inputs. Use a digest-pinned Ubuntu 24.04 image and
a pinned snapshot.ubuntu.com snapshot ID for build packages, recording toolchain
and package versions. Do not maintain a separately published builder image initially.
GitHub Actions dependencies use full commit SHAs.

Support Git-based dependencies such as x264 by locking the repository URL and full
commit SHA. Generate a deterministic source archive with pinned tooling and record
its SHA256; publish that exact archive as corresponding source. Include any required
submodules at their locked commits. Never resolve a moving branch during a build.

Previously verified source archives:

- MuPDF: `https://github.com/ArtifexSoftware/mupdf-downloads/releases/download/1.28.4/mupdf-1.28.4-source.tar.gz`, SHA256 `2d97e043a616f96b148657c9c3d81ad71c4bd2052c59a2a3315ad842599340f9`.

MuJS is included in the locked MuPDF source archive; no separate download or
replacement. Verified against upstream on 2026-09-20: the bundled commit contains
`REG_MAXCLASS 128` and descends from the fix that raised the limit from 16.
It is only two commits behind the latest MuJS release, 1.3.10: those add optional
runaway-regexp detection and an internal class check in Array.prototype.sort.
They do not change the character-class limit. This is close to the latest release,
not identical to it. Use the upstream-tested bundle as explicitly approved.

Evidence: [bundled source](https://github.com/ArtifexSoftware/mujs/blob/e892c9fdbbddba94e52f656ccb378ed4885e30cc/regexp.c#L26),
[comparison with 1.3.10](https://github.com/ArtifexSoftware/mujs/compare/e892c9fdbbddba94e52f656ccb378ed4885e30cc...1.3.10).
This verification is source-level; the packaged-mutool regression below remains
a required release check.

Before implementation merges, independently verify all downloads, fill the FFmpeg
and dependency hashes, and verify FFmpeg's detached release signature against its
pinned upstream signing-key fingerprint. Verify hashes before extraction. Commit
all inputs; a version lacking a verified source lock cannot be released.

## Build design

Use Ruby orchestration for per-tool recipes and shared packaging/test entry points,
invoking upstream configure/make commands. Run CI jobs on native AMD64 and ARM64
VM runners, not inside GitHub job-level containers. The same Ruby entry point
prepares pinned build images and inputs with Docker, then invokes `docker run
--network none` for configuration and compilation, locally and in CI.
Target Ubuntu 24.04 as the oldest supported runtime;
verify the same archives on Ubuntu 24.04 and Debian 13 minimal containers. No
`-march=native`; use portable architecture defaults. macOS, Windows, and musl/Alpine
are unsupported initially.

Apply CPU portability to every dependency, not only top-level compiler flags.
Configure generic CPU targets or runtime dispatch where supported (including GMP,
nettle, and libvpx); inspect generated flags for build-host CPU tuning. Document
the baseline CPU requirements and smoke-test the packaged tools with baseline
x86-64 and ARMv8.0 CPU models under emulation, exercising codecs and TLS as well
as version output. Native runtime tests remain required alongside these checks.

Separate input acquisition from compilation: fetch and verify locked sources and
install pinned build packages with network access, then run configuration, build,
packaging, and local tests in containers with `--network none`. Pre-fetch required
submodules and build-system inputs; missing inputs must fail rather than trigger
network fallbacks. This restriction concerns build-time access only.

Prefer static linkage of tool-specific dependencies while retaining system glibc,
libm, and the dynamic loader. Audit ELF needed libraries, interpreter, and symbol
versions; publish the exact runtime dependency allowlist. Do not silently acquire
runtime libraries from the build host. If an unavoidable dependency remains,
explicitly package it with relative loader paths or declare/install it in both
consumer environments and test that contract before release.

### MuPDF

Use MuPDF's bundled MuJS unchanged, recording its exact upstream commit.
Build `mutool` with bundled libraries and system MuJS disabled; disable unused GUI,
OpenGL/X11, curl, and crypto integrations only where existing app operations still
pass. The existing private consumer's tested build is feasibility evidence, not a
public source dependency. Keep this repo independently buildable.

Record embedded MuJS commit and source hash in build metadata: `mutool -v` alone cannot
prove its JavaScript engine version. Regression: execute a JavaScript regexp with
32 repeated character classes through `mutool run`; it must compile and match.
Older MuJS engines limited these regexps to 16 classes. This checks the engine
actually embedded in mutool, not a separate executable.

### FFmpeg

Build `ffmpeg` and `ffprobe` from the same pinned release, without ffplay or GUI
stacks. First inventory consumers' command lines and installed `-buildconf`,
`-formats`, `-decoders`, `-encoders`, and `-filters`. Record the supported feature
matrix and use consumer requirements to catch omissions, not to trim native
components. Do not promise parity with every distro feature.

Keep broad common audio/video support, including encoding, rather than trimming
to today's call sites. Retain FFmpeg's default-enabled native components, including
parsers and bitstream filters; never use `--disable-everything`. Add
x264, x265, libvpx, libopus, libmp3lame, and libdav1d for software AV1 decoding.
Also include libvorbis and libwebp encoding, pinned SVT-AV1 (`libsvtav1`) encoding,
FreeType/HarfBuzz and libass with their dependencies for drawtext and subtitles,
and an x265 multilib build supporting both 8-bit and 10-bit HEVC encoding.
Include Fontconfig support for font discovery and pinned GnuTLS plus its required
dependencies for HTTPS input. Enable GnuTLS explicitly in FFmpeg's configuration.
Pin and compile these external dependencies; record their versions and licenses.
The resulting GPL-enabled FFmpeg build is deliberate. Do not enable nonfree or
nonredistributable combinations, GUI stacks, or hardware-specific integrations.

Keep FFmpeg's automatic dependency detection enabled, as explicitly requested.
Use the pinned build environment and inspect the resulting feature inventory;
required codecs and filters must pass checks even when configure succeeds.
Do not add `--disable-autodetect`. Explicit enables for libraries that require
opt-in remain compatible with automatic detection of other available dependencies.

Minimum test coverage: MP4/H.264/AAC, MOV with rotation metadata, WebM/VP8/VP9/Opus,
MP3, PCM/WAV, HEVC and AV1 software decoding, and JPEG/PNG output. Include OGA-to-MP3
conversion with `-acodec libmp3lame`, required by notetoself, and round trips for
the selected common encoders. The inventory catches gaps; it does not restrict
support to current use. Publish the supported feature matrix explicitly rather
than claiming parity with every distro feature.
Include encode/decode checks for Vorbis, WebP, and AV1; verify 8-bit and Main10 HEVC
output. Test drawtext and subtitle rendering using a redistributable fixture font
and subtitle file, and document any runtime font/data requirements.

Do not bundle fonts in the runtime-tool archive. Consumers using text/subtitle
features install Fontconfig configuration and a font package; document the expected
paths and verify font discovery in both supported runtimes. Test rendering with
fonts installed and the missing-font case with a clear diagnostic. Keep fixture
fonts in tests only. Document the system CA trust-store requirement for HTTPS input;
verify certificate validation using a controlled HTTPS fixture in a separate
integration check, without enabling network access during compilation.

Configure GnuTLS with
`--with-default-trust-store-file=/etc/ssl/certs/ca-certificates.crt` so trust-store
discovery does not depend on the builder. In both supported runtime images, install
a fixture CA into the system store and verify HTTPS succeeds without a `-ca_file`
override; reject an untrusted certificate. These checks are required for release.

Configure Fontconfig with `--sysconfdir=/etc --localstatedir=/var
--with-default-fonts=/usr/share/fonts`. Audit compiled-in data/config paths for all
static dependencies, not only ELF loader paths. Use fixed container build paths
locally and in CI, remap source/debug paths with compiler prefix-map options, and
set FFmpeg's runtime data directory explicitly. Inspect embedded build paths but
distinguish informational configure/build metadata from runtime lookups: metadata
may describe the fixed build environment; runtime paths must never require it.
Document a writable font-cache location for non-root
consumers and test font discovery/rendering with that configuration.

## Artifacts and release contract

Use separate release series so MuPDF and FFmpeg can update independently:
`mupdf-1.28.4-r1` and `ffmpeg-9.0.2-r1` initially. Archive names include
that release ID and `linux-amd64` or `linux-arm64`.

Binary archives use gzip-compressed tar: `<release-id>-linux-<arch>.tar.gz`, with
one root directory `<release-id>-linux-<arch>/` containing `bin/`, `licenses/`, and
`build-info.json`. Consumers need no xz or zstd dependency. Include versions,
source hashes, build commit, configure flags,
toolchain identity, architecture, runtime requirements, and dependency inventory.
Publish SHA256SUMS plus complete corresponding source archives, patches, recipes,
and required license/notices alongside the binaries. Establish redistribution
requirements for the actual selected licenses, including MuPDF and FFmpeg codec
libraries, before publishing. A public repository alone is not a compliance step.
No private application code, invoice data, credentials, or private fixture assets.

PR checks build/test without release-write permission. A manually triggered release
workflow builds the default-branch commit captured by the dispatch, tests both
architectures, and creates a draft
release only after all jobs pass. Publishing the reviewed draft is a separate
explicit human action. Only the release job has `contents: write` via the repo's
GITHUB_TOKEN; consumers require no token. Never run publishing from PR code.

Restrict release dispatch to the default branch and reject other refs. Build the
dispatch event's exact `github.sha`; accept no arbitrary source-SHA input. Use that
SHA throughout checkout/build/test and as the draft/tag's explicit target, even if
the branch advances during the run. Configure default-branch rules
requiring PRs and passing checks and preventing force-pushes, protect `mupdf-*` and
`ffmpeg-*` release tags, and restrict the release environment to the default branch.
These controls do not make administrator bypass impossible or require an unavailable
second maintainer's approval. Configure them during later release setup, not during
this planning task.
Enable GitHub immutable releases before first publication and verify the published
release is immutable. Attach GitHub build-provenance attestations for the exact
tested archive digests, with attestation/OIDC permissions scoped to the trusted
release path. Retain the per-release concurrency group and existing-asset refusal.

Publish the tested archives, without rebuilding between tests and release. Fail if
release names or asset paths already exist; never clobber assets or retag. Set
`make_latest=false` and document explicit tag-based URLs only, since both tools
share this repository. Increment `rN` for corrections and dependency, build-flag,
or toolchain changes, even when the upstream tool version stays the same. Include
the lock-file diff in release notes. Store source and binaries together
for long-term availability; Actions' temporary artifact retention is insufficient.
Missing architecture, tests, checksums, or required source/license files blocks the
whole tool release. Serialize concurrent publication attempts per release ID.

Document failed-upload recovery in the release runbook. If an incomplete draft
already exists, stop with its URL and instructions for a human to verify it was
never published and delete the draft before retrying. Never automatically overwrite
or delete assets. Published releases and existing tags remain protected; if a tag
already exists, stop for human inspection and use a new revision rather than retag.

## Verification

Test the extracted release archives, not just build-tree binaries, on both
architectures and both supported operating systems with no compiler or undeclared
libraries installed. Check versions, embedded engine regression, metadata, ELF
runtime dependencies, and the absence of build-directory paths in runtime loading.

Public MuPDF tests use generated, redistributable synthetic PDFs to exercise the
tool APIs used by consumers: structured-text `asText()`, the `search()` result
shape, Redact annotations and `applyRedactions`, embedded XML attachment survival,
and `mutool draw -F png` rendering. Verify redacted text disappears while unrelated
text remains. Invoice wording, ambiguous matches, and idempotence are consumer
logic; keep those tests in Baseline's Qonto suite as a later migration gate.

FFmpeg tests probe fixture JSON for streams, dimensions, duration (with tolerance),
and rotation. Commit literal argv fixtures captured from the consumer's ActiveStorage
previewer and analyzers, including configured `video_preview_arguments`, annotated
with their Rails version. Run these fixtures against the packaged tools without
requiring Rails in this public repository. Actual Rails integration tests remain
in Baseline and catch changes when Rails is upgraded.
Rails' video preview output is JPEG: validate
JPEG decoding, dimensions, and content, including required filters and the mjpeg
encoder/image2 output path. Keep PNG generation as additional tool coverage.
Exercise the supported format matrix plus any selected
encoders with encode/decode round trips. Use checked-in small redistributable input
fixtures or independently generated pinned inputs, so tests do not depend on the
same encoder producing every file they decode. Compare feature lists between
architectures. Do not require byte-identical output across codecs or architectures.

Validate workflow syntax and recipe failure propagation. Record repeat-build
hash comparisons, but do not claim bit-for-bit reproducibility until demonstrated.

## Consumer integration (separate follow-up)

At planning time Baseline main uses distro packages. The source-build installer
exists in the investigation worktree and has not landed; do not assume it is the
consumer baseline. Inspect the actual target revision when implementing migration.

After approved artifacts exist, update Baseline's shared installer to select an
explicit release URL and committed per-architecture SHA256, verify before unpacking,
and install the predictable binary layout. Never execute a downloaded installer.
Map Docker TARGETARCH and host architecture explicitly; no host/target confusion.
Both Docker builds and CI use the same pins and verification code. Preserve any
required license/metadata files in container images. Fetch over public HTTPS without
GitHub credentials. No fallback to apt or latest after download/checksum failures.

Installer tests live in Baseline: reject wrong checksums, unsupported architectures,
missing assets, unsafe archive paths, and incomplete archives before installing.
Verify and extract in temporary staging, or abort the Docker/CI step. Do not add
an in-place upgrade/rollback mechanism for these disposable build environments.

Remove superseded source compilation and distro tool packages only after proving
all required executables and consumers are covered. Verify actual PATH selection
and versions inside final app containers and CI; ensure another apt dependency does
not cause an old binary to win. Run private Qonto tests, Rails PDF/video preview and
metadata tests, relevant repository checks, and final-container smoke tests. Leave
Poppler and the Rails previewer order unchanged in this migration.

Rollback restores the prior explicit release/checksum pair. Keep old releases
available. Updates follow a reviewed manifest change, complete build/test/release,
then a separate consumer pin change. Upstream update notifications may prompt work;
they never publish or advance consumers automatically.

## Implementation sequence and acceptance

1. MuPDF milestone: finalize its source lock, licenses, fixture rights, and runtime
   allowlist; implement its native builds, packaging, and regression/API tests.
2. Add the shared read-only CI matrix and manual draft release workflow; validate
   failure paths and permissions without publishing a release.
3. Human review; explicit MuPDF draft creation/publication when authorized. Verify
   public downloads, checksums, and source completeness. Its separate Baseline
   integration can proceed without waiting for FFmpeg's inventory or build work.
   Before first publication, revisit relevant deferred decisions and record whether
   each is accepted for implementation or remains explicitly deferred.
4. FFmpeg milestone: finalize its broad feature matrix and dependency/license locks;
   implement builds and tests using the same release pipeline. Independently review
   and publish when authorized, then integrate its pins in a separate consumer change.
   Before its first publication, likewise revisit and record decisions on the
   relevant deferred findings.
5. Each consumer change runs relevant private regression and final-container checks.
   Deployment and manual resolution of the original error remain separate.

Done for the implementation: both tools produce verified archives for both Linux
architectures; both supported runtimes pass the feature/regression matrix; consumers
can install exact reviewed artifacts without private tokens; update and rollback
instructions are documented. This plan does not itself certify those checks passed.

## Manual review decisions

- Finding 1 applied: retain bundled MuJS after verifying the regex-limit fix and
  its two-commit distance from 1.3.10. Remove the separate MuJS source pin and
  simplify the release ID; keep the embedded-engine runtime regression.
- Finding 2 applied with the user's broad-support preference: require LAME and
  OGA-to-MP3 coverage, software AV1 decoding, and common external encoders. Reject
  narrowing to an LGPL-only feature set; avoid hardware-specific and nonfree builds.
- Finding 3 deferred by the user: a formal security/update monitoring policy and
  proposed network restrictions remain unresolved, outside this plan revision.
- Finding 4 applied: independent MuPDF-first and FFmpeg-second milestones; clarify
  that the source installer is pending work and current main uses distro packages.
- Finding 5 applied: test actual configured Rails argv and JPEG previews; retain
  PNG as additional coverage.
- Finding 6 applied: public tests cover tool APIs; installer failures and invoice
  business logic are tested in the Baseline follow-up.
- Finding 7 applied: default-branch-only release dispatch, explicit target SHA,
  protected release controls, immutable releases, and build provenance. Repository
  settings are future implementation work; none changed during planning.
- Finding 8 applied: digest-pinned Ubuntu 24.04 with a fixed package snapshot and
  Ruby orchestration; no separately maintained builder image initially.
- Finding 9 applied: support full Git commit pins and deterministic, checksummed
  source archives for dependencies without suitable release archives.
- Finding 10: user rejected disabling automatic detection. Keep it enabled and
  validate required features in the pinned build environment.
- Finding 11 applied: include Vorbis/WebP/AV1 encoding, text/subtitle rendering,
  and 8-bit/10-bit HEVC encoding, with dependency pins and regression coverage.
- Finding 12 deferred by the user: independent verification of the bundled MuJS
  tree against a commit-specific content hash remains unresolved. The complete
  MuPDF archive checksum and embedded-engine regression remain required.
- Finding 13 applied: `.tar.gz` binary archives with a fixed release/architecture
  root directory.
- Finding 14 applied: fetch and verify inputs first; configure, compile, package,
  and run local tests without network access.
- Finding 15 applied: disable the Latest designation, use explicit tag URLs, and
  increment release revisions for all dependency/configuration/toolchain changes,
  documenting lock-file differences.
- Finding 16 applied: specify achievable branch/tag/environment protections and
  acknowledge administrator bypass without requiring a second maintainer.
- Finding 17 deferred by the user: mandatory review gates on per-architecture
  feature/runtime-library inventory differences remain unresolved.
- Finding 18 applied: release builds use the default-branch dispatch's exact
  `github.sha`, with no arbitrary source-SHA input.
- Finding 19 deferred by the user: a separate release/PR compiled-cache policy
  remains unresolved.
- Finding 20 deferred by the user: downloading and reverifying draft release assets
  before publication remains unresolved; existing archive tests still apply.
- Finding 21 applied: Fontconfig support with consumer-installed configuration and
  fonts, plus tests with and without fonts. No fonts bundled in tool archives.
- Finding 22 applied: explicitly include pinned GnuTLS and its dependencies for
  HTTPS input, document CA trust requirements, and test certificate validation.
- Finding 23 applied: retain FFmpeg's default native components and autodetection;
  select SVT-AV1 for software AV1 encoding.
- Finding 24 applied: commit Rails-version-annotated literal argv fixtures here;
  retain live Rails integration coverage in Baseline.
- Finding 25 applied: native VM CI jobs use the same Ruby/Docker entry point as
  local builds, with offline configuration/compilation containers.
- Finding 26 applied: explicit GnuTLS system trust-store path and required positive
  and negative certificate-validation tests using the system store on both runtimes.
- Finding 27 applied: explicit Fontconfig runtime paths, staging-path checks for
  static dependencies, and documented/tested writable font-cache configuration.
- Finding 28 applied: generic CPU targets/runtime dispatch throughout dependencies
  and baseline-CPU emulated smoke tests alongside native runtime tests.
- Finding 29 applied: describe the source as the default-branch commit captured by
  dispatch, without asserting administrator bypass cannot occur. Finding 26 already
  makes HTTPS certificate checks required for release.
- Finding 30 applied: distinguish informational build metadata from runtime lookup
  paths, use fixed build paths and compiler prefix maps, and set runtime data paths.
- Finding 31 applied: document human cleanup of an unpublished partial draft before
  retrying, preserving published releases and existing tags.
- Finding 32 applied: revisit and explicitly accept or continue deferring relevant
  findings before each tool's first publication.

Review status: five Fable rounds completed in manual mode. Findings 3, 12, 17, 19,
and 20 remain explicitly deferred; disabling autodetection was rejected in finding
10. All other findings were applied, with the user's broad-codec preference for
finding 2. Changes from findings 30–32 were not rechecked by Fable because the
five-round limit was reached. This is a reviewed plan, not verified implementation.
