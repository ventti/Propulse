# Contributing to Propulse Tracker

This guide covers building Propulse from source, the conventions used in the
codebase, and the release process. If you just want to use the tracker, see the
[README](README.md).

## Building

Propulse is written in FreePascal and built with CMake. The release pipeline
currently produces binaries for **macOS (ARM64)** and **Windows x64** — these
are the targets with bundled runtime libraries (`lib/`) and packaging workflow
presets. Configure presets for macOS x86_64 and Linux (x64/ARM64) also exist,
but they are not part of the build pipeline (no bundled libs, no workflow
presets) and are not currently built or tested. 32-bit x86 targets are not
supported.

### Requirements

- **FreePascal 3.2+** with cross-compiler support for the targets you want to
  build. The easiest way to install FPC and the cross-compilers/RTL units is
  [fpcupdeluxe](https://github.com/LongDirtyAnimAlf/fpcupdeluxe).
- **CMake 3.x**.
- A C toolchain (Xcode command-line tools on macOS).
- Bundled runtime libraries (SDL2, BASS, libSOXR) live in `lib/` and are
  committed to the repo. BASS is required for MP3/Ogg sample import; libSOXR is
  used for high-quality resampling.

Lazarus is **not** required.

### macOS (ARM64) quick start

```bash
./install-fpc-mac.sh     # install FPC (+ cross-compilers) via fpcupdeluxe
./bootstrap-mac.sh       # check the toolchain and dependencies
```

Then configure and build with CMake presets:

```bash
cmake --preset macos-arm64-release
cmake --build --preset macos-arm64-release
```

Or run the whole configure + build + package step in one go with a workflow
preset:

```bash
cmake --workflow --preset macos-arm64-release
```

### Available presets

The targets that are actually built and packaged have `release`/`debug` and
workflow presets:

- `macos-arm64-release` / `macos-arm64-debug`
- `windows-x64-release` / `windows-x64-debug`

Configure presets for `macos-x86-*`, `linux-x64-*` and `linux-arm64-*` are also
defined, but they lack bundled libraries and workflow presets and are not part
of the build pipeline.

List the presets at any time with:

```bash
cmake --list-presets           # all configure presets
cmake --list-presets=workflow  # only the targets the pipeline builds
```

### Building all release targets

`build-all-releases.sh` cleans the build/release directories, validates
`data/help.txt`, runs every workflow preset (currently macOS ARM64 and Windows
x64), and writes a `git describe` version into `release/`. Building the Windows
target from macOS requires the Windows cross-compiler/RTL units to be installed.

```bash
./build-all-releases.sh
```

The build version is derived from `git describe --always --tags --dirty`, so
tag before building if you want a clean version string baked into the binaries.

## Conventions

### Pascal / FreePascal

- Make only the explicitly requested change, and keep it as small as possible.
- Don't mix refactors with behavior changes; avoid style-only rewrites.
- Preserve the existing architecture and invariants. Reuse existing code and
  patterns instead of adding parallel implementations.
- Don't add dependencies unless explicitly allowed. Assume data formats and the
  API/ABI are stable, and flag any compatibility impact.
- Behavior changes need tests; high-risk areas need stronger coverage.
- Follow FPC conventions, keep functions focused, and comment only complex
  logic.
- **FPC ICE safety:** use a single related `const` block and avoid consecutive
  `const` blocks. If an internal compiler error appears, try minimal syntax
  reshapes first.
- Avoid implicit conversions in hot paths; prefer concrete types/overloads and
  keep any required conversion explicit and local.

### Documentation & help

- If you change a mouse or keyboard shortcut, update `data/help.txt`
  accordingly (`build-all-releases.sh` validates the help text).
- Keep documentation consistent with the code; document intent and assumptions,
  not obvious code.

### Build & tooling

- Keep build artifacts out of the repo (respect `.gitignore`). The libraries in
  `lib/` are committed despite `.gitignore`.
- Reuse existing scripts instead of adding parallel ones.

### Commit messages

Use single-line, lowercase, present-tense imperative
[Conventional Commits](https://www.conventionalcommits.org/):

```
add undo/redo system to sample editor
fix soxr detection on macOS by preventing automatic disable
improve orderlist: show dots for unused entries and auto-expand on input
```

- Lowercase, no trailing period.
- Be concise but descriptive; use a colon to add detail when helpful.
- Group related changes into minimal, logical commits.

To use the provided commit template:

```bash
git config commit.template .gitmessage
```

See [COMMIT_CONVENTIONS.md](COMMIT_CONVENTIONS.md) for more examples.

## Releasing

`release.sh` ties the release process together (build, changelog, upload, and
GitHub release creation):

```bash
./release.sh                      # pre-release, no new tag
./release.sh --pre minor          # bump version, tag X.Y.Z-pre, no GitHub release
./release.sh minor                # bump version, tag X.Y.Z, create GitHub release
./release.sh --promote            # promote the latest X.Y.Z-pre to a full release
```

The working tree must be clean before tagging a release. Uploading to Dropbox
requires a configured `.dropboxuploader`, and creating a GitHub release requires
the `gh` CLI.
