# Legacy documentation

> **Disclaimer:** The files in this directory are **legacy documentation from
> Hukka's original Propulse Tracker** (the 0.9.x line and earlier). They are kept
> for reference and historical context. They predate the **Extended** fork and
> are *not* maintained — some of what they describe has since been implemented,
> changed or replaced.
>
> For an up-to-date list of what changed in the Extended fork, see the
> [CHANGELOG](../CHANGELOG.md). To build from source, see the
> [Contributing guide](../CONTRIBUTING.md), not the files here.

## What's in here

- `whatsnew.txt` — Hukka's release notes for Propulse 0.9.x.
- `status.txt` — project status and notes against the original PoroTracker base.
- `building.txt` — original build instructions.
- `images/` — screenshots used by the project README.

## Outdated or superseded content

The items below are described in these docs but have since been implemented or
modified in the Extended fork. See the [CHANGELOG](../CHANGELOG.md) for details.

### Build instructions (`building.txt`)

Obsolete. The original docs describe a Lazarus/Makefile build with 32-bit x86
targets and `Shift-F9` in the IDE. The project has since migrated to a **CMake**
build system, builds **without Lazarus**, dropped 32-bit x86 support, and
currently produces prebuilt binaries for macOS (ARM64) and Windows x64. See
[CONTRIBUTING.md](../CONTRIBUTING.md).

### Project status (`status.txt`)

- "Need someone else to do the Mac binary builds" — no longer true; macOS ARM64
  builds and a cross-platform CMake build/packaging pipeline now exist.
- "Some file operations are untested on non-Windows platforms" — out of date;
  cross-platform paths have been worked on, including loading dropped files with
  non-ASCII names on Windows and macOS dylib path handling.

### Features modified since 0.9.x (`whatsnew.txt`)

- **Playback cursor/view restore** — the original "pattern view is restored on
  stop" behavior has been extended with `F2`/`F7`/`F8`/`Shift-F7`/`Shift-F8`
  resume-and-restore controls.
- **S3M and IT import** — now reads tempo and speed from the file headers, with
  several IT loader fixes (zero params, fine volume slide conversion, channel
  allocation for split patterns).
- **Sample editor** — beyond the original double-click selection, the Extended
  fork adds mouse-driven waveform drawing (`Ctrl`+left button) and a full
  undo/redo system.

## Features added since these docs were written

These docs predate several Extended features that they therefore do not mention:

- Full **undo/redo** in the pattern editor, order list and sample editor.
- **Mouse-based block selection** in the pattern editor.
- **Autosave**.
- Per-module **notes / metadata**.
- **Command-line arguments** (including showing the build version).
- **Channel solo** toggle (`s`) during playback.

See the [CHANGELOG](../CHANGELOG.md) for the complete list.
