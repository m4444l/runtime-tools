# Build and release runbook

## Before the first release

Configure GitHub immutable releases. Require PRs and passing CI on main, prohibit
force-pushes, and protect `mupdf-*` and `ffmpeg-*` tags against updates/deletion.
Allow the release workflow to create new tags; do not configure a creation rule
that blocks its repository-scoped GITHUB_TOKEN. Set the `release` environment to
allow the default branch only. Administrator bypass remains possible. No private
read token or other repository's credentials are needed.

These settings are prerequisites managed by the human; running build/test commands
does not change repository settings. Review the selected upstream licenses and
corresponding source before distributing binaries. Source bundles include the exact
locked upstream archives, recipes, lock, and notices; inspect them for completeness.

Revisit deferred decisions 3, 12, 17, 19, and 20 from the plan for each tool's first
publication; explicitly record implementation or continued deferral. Do not silently
interpret a deferred item as resolved. Review final implementation validation and
remaining platform limitations before triggering the draft workflow.

## Prepare a draft

1. Merge the reviewed implementation/version change, including source hashes and
   any new release revision. Both architectures and both runtimes must pass CI.
2. Manually dispatch **Prepare draft release** on the default branch and select
   `mupdf` or `ffmpeg`. It builds the exact dispatch SHA, compiles offline, tests
   extracted archives, validates source bundles and both verification reports,
   attaches provenance, and creates a draft. It never publishes automatically.
3. Inspect the draft, license/source files, SHA256SUMS, build metadata, provenance,
   and test reports. Publish manually only when satisfied. Verify immutability
   after publishing and anonymous download access and digest equality.
4. Use explicit URLs such as
   `https://github.com/m4444l/runtime-tools/releases/download/mupdf-1.28.4-r1/mupdf-1.28.4-r1-linux-amd64.tar.gz`.
   Never use `/latest/`. Both release series intentionally suppress Latest.
5. Change the consumer's explicit URL and SHA256 in a separate reviewed change.
   Run consumer Qonto/preview/metadata regressions and final-container checks.

A failure never overwrites assets. If a failed upload leaves a draft, inspect its
URL and confirm it has never been published. A human may delete that draft and
retry. Existing tags and published releases remain protected: use a new `rN`
instead of moving a tag. No automatic cleanup or publication is performed.

## Updates and rollback

Update exact versions, source hashes, commits, image digests and snapshot date in
`config/lock.json`. Git dependencies are archived at the full pinned commit using
`git archive --format=tar --prefix=<source-name>/`; lock the resulting checksum.
Do not substitute an upstream-generated archive without updating and reviewing
that checksum. Source re-fetches always reverify cached bytes.

For FFmpeg, verify its detached release signature against the pinned signing-key
fingerprint, update the committed signature/key when appropriate, and review codec
features and runtime libraries. Build-time package versions are recorded from the
pinned Ubuntu snapshot. `config/bootstrap-ca.pem` is curl's Mozilla CA export used
only to bootstrap signed apt snapshot access; the runtime installs distro CA trust.

Increment `rN` whenever dependencies, flags, recipes or toolchain change, even if
the tool version is unchanged. Release notes include the lock diff. Keep old public
releases so rollback means restoring the prior URL/checksum pair. Upstream changes
do not automatically advance the lock or consumers.

## Local validation

`verify` tests Ubuntu and Debian separately with no compiler installed, checks
MuJS's 33-class regexp through the packaged mutool, PDF search/redaction/attachments,
media codecs, Rails command fixtures, font support, and the TLS system store. It
also runs the binary smoke suite under baseline CPU emulation. The HTTPS test uses
a loopback fixture only; compilation remains offline. Verification reports bind
successful tests to the archive SHA256 and runtime image digests. CI checks the
same artifacts which the release job uploads.

This repository does not install binaries into app containers or change Baseline.
The installer must verify the committed SHA256 before extraction, reject unsafe
archive paths, keep required metadata/licenses, and fail without fallback to latest.

The release workflow records a second clean build's archive hash in a
`.reproducibility.json` report; differing hashes are reported, not hidden or
advertised as reproducible. FFmpeg releases also include a cross-architecture
feature comparison. Feature differences are informational pending the deferred
mandatory-review policy. Provenance can be checked with
`gh attestation verify ARCHIVE --repo m4444l/runtime-tools`.

Extracted corresponding-source bundles can rebuild without Git metadata: the
included `source-info.json` identifies the original commit and the CLI uses the
bundled source archives. Such local rebuilds are marked as non-release working
copies; only a clean workflow checkout can supply publishable release assets.
