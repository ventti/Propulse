# Changelog

## 0.11.0 - 2026-07-27

- fix(keys): ignore stale config bindings whose name no longer matches a default so they can't shadow live shortcuts (fixes Tab in sample list) (`7c07b29`)

## 0.11.0-rc.1 - 2026-07-27

- build: add mise task runner with local build task and remote release catalog (`b0c4a24`)
- chore(release): remove legacy shell release scripts superseded by mise tasks (`3b28ef5`)
- fix(keys,editor): restore Tab in sample list and keep order list centered on playhead past 32 patterns (`24d123c`)
- fix(keys): resolve shortcut conflicts so one command owns each shortcut; load user config after defaults; rebind Metadata.Previous to Ctrl+Shift+B (`ba72a77`)
- feat(ui): add fuzzy command palette (Ctrl+E) as a filterable variant of the main menu (`17e08eb`)
- feat(editor): interpolate volume (Alt-K) and effect (Alt-X) values with keep-other-column variants (Alt-Shift-K/X); rebind wipe effects to Alt-W (`9625391`)
- fix(editor): restore channel separator glyph (168) instead of superscript-2 (`3bb654d`)
- feat(editor): click a channel title to mute/unmute it; ctrl/right-click solos it (`505ee13`)
- fix(editor): default the volume column edit-mask (,) to off (`5db7bc6`)
- feat(release): add --ignore-missing and --verbose to upload-release-dropbox.sh; quiet by default (`1ec309e`)
- fix(release): validate release artifacts before uploading to Dropbox to avoid partial uploads (`a52d093`)
- chore(release): add -h/--help to the release helper scripts (`7530a70`)
- refactor(release): split push/gh release into upload-release-github.sh, rename uploader to upload-release-dropbox.sh (`e4f848e`)
- docs: document note system rationale and status set (`0652b8d`)
- feat(import): create info notes for each S3M/IT conversion issue (`178f705`)
- feat(notes): editable ticket-style notes with statuses, filter/sort, free-form body and undo/redo (`1186eee`)
- chore: update gitignore (`999b755`)
- docs: add changelog, contributing guide, docs README and refresh main README (`94edb49`)
- fix: honor comma edit-mask for volume and effect columns on note entry (`736b883`)
- fix: make github release idempotent, non-interactive, with empty notes (`ffa9402`)

This is the changelog for the **Extended** fork of Propulse Tracker. It collects
the work done on top of the original tool, grouped by area rather than by release.

## Extended version

### Pattern editor

- Full undo/redo system for the pattern editor.
- Mouse-based block selection, with double-click to toggle selection.
- Undo support for block paste, clear, swap and effect operations.
- Jump to the current playback position in the pattern editor.
- Mouse-click navigation on pattern and order labels.
- Replace-sample now stays in sync with the sample list selection; fixed an
  off-by-one when replacing a sample throughout the patterns.
- `alt+e` marks the block end at the cursor instead of mirroring `alt+b`.
- Insert-paste no longer writes overflowing rows.
- Fixed a crash on cut/copy with no active selection.

### Order list

- Undo/redo extended to the order list, restoring the cursor position.
- Unused entries are shown as dots, and the list auto-expands on input.
- Double-click an order entry to switch to its pattern.
- Order cursor stays in sync with the pattern selection across all selection
  methods.
- Unused order slots are zeroed on save to prevent a pattern-count mismatch.
- `space` no longer truncates the order list.

### Playback

- Toggle channel solo during playback with `s`.
- `F7` / `Shift-F7` resume playback from the stored order/row position;
  `F8` / `Shift-F8` control whether the cursor returns to the start or stays.
- `F2` restores the edit cursor and pattern scroll position during playback.
- Order label shows dots during pattern-only playback.
- Various playback start-position and cursor-sync fixes.

### Sample editor

- Full undo/redo system for the sample editor.
- Mouse-driven waveform drawing with `Ctrl`+left mouse button.
- Sample swap now swaps two entries in place instead of shifting the whole list,
  and a single undo reverses the entire swap.
- Sample playback no longer retriggers on key auto-repeat in the sample list.
- Fixed a cleanup crash when truncating cleared looped samples.

### File formats

- Improved S3M and IT import: tempo and speed are now read from the file headers.
- IT loader state is reset correctly and explicit zero parameters are handled.
- IT fine volume slide up is converted to `EAx` instead of `Axy`.
- Enough channels are allocated for split patterns to prevent IT import crashes.
- Dropped files with non-ASCII names now load correctly on Windows.

### Module metadata / notes

- Ticket-style **notes** for a song (`Shift+F4`): a per-song TODO list,
  descriptions, sheet-music snippets and ideas — meant to replace the scattered
  text files and paper notes that pile up during composition, and to keep that
  information linked to where it actually matters.
- Each note can **point at the spot it's about** — a pattern cell
  (channel/row/column), an order position, a sample, or a pattern selection — and
  **Go To** jumps the editor straight there.
- Notes are ticket-like: a stable, always-increasing ID plus a status
  (`open` / `todo` / `fix` / `wip` / `done` / `old` / `info`). Next/previous
  navigation skips `old` and `done`; deleting a note warns first and offers to
  mark it `old` instead, so the running history is preserved.
- The body is an ordinary multiline text editor (cursor movement, normal ASCII).
- Stored in a **sidecar** file (`<module>.json`) next to the module — the notes
  do **not** ship inside the song file, so they stay private unless you choose to
  share the sidecar too.

### Autosave & robustness

- Autosave support, with timestamps on log messages.
- Custom exception handler with stack-trace output.
- Added null checks and exception handling around module operations.
- Fixed a save crash when the filename was empty or a directory.

### Interface & help

- Type-to-search in the help viewer; `Shift-F1` reopens help at the last
  position.
- Inline numeric entry in the configuration list.
- File-requester search looks through both panes and moves focus to the match;
  text input takes priority over global shortcuts.

### Command line

- Command-line argument support, including showing the build version.
- The actual build version is now shown everywhere instead of a hardcoded value.

### Build system & packaging

- Migrated from the Makefile to a CMake build system using toolchain files and
  multi-inheritance presets.
- Cross-compilation presets for macOS (ARM64 and x86_64), Windows x64 and Linux
  (x64 and ARM64); 32-bit x86 targets were deliberately dropped. The release
  pipeline currently builds and packages macOS ARM64 and Windows x64.
- Bundled SDL2, BASS and libSOXR libraries; soxr resampling enabled, with
  automatic macOS dylib path fixing.
- Build version derived from `git describe`.
- Release tooling: `release.sh` (version bump, pre-release and promote modes),
  `build-all-releases.sh`, changelog generation and upload to Dropbox and
  GitHub Releases.
- The project now builds without Lazarus.
- Various FreePascal internal-compiler-error (ICE) workarounds.

### Branding

- Marked as the Extended fork to distinguish from the original Propulse Tracker. 
- Updated project URL
