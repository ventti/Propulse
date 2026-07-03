# Propulse Tracker (Extended)

A crossplatform tracker for making Amiga ProTracker compatible modules using an
Impulse/Schism Tracker style user interface.

This is the **Extended** fork, with an undo/redo system, a mouse-driven sample
editor, autosave, module notes, expanded import support and more. See the
[changelog](CHANGELOG.md) for the full list of changes.

A crossplatform codebase that runs on Windows, Linux and macOS. Prebuilt
binaries are currently produced for macOS (ARM64) and Windows x64.

![Editor screenshot](https://github.com/hukkax/Propulse/blob/trunk/docs/images/ss1.png)

## Features

- Super accurate playback engine based on work by 8bitbubsy (itself based on a
  disassembly of the original Amiga ProTracker); things like `black_queen.mod`
  and the MPT test cases play correctly.
- Familiar Impulse/Schism Tracker-ish interface with familiar keyboard commands.
- Full undo/redo in the pattern editor, order list and sample editor.
- Mouse-based block selection in the pattern editor and mouse-driven waveform
  editing in the sample editor.
- Autosave, plus per-module notes/metadata.
- Flexible playback controls for resuming and following the song during editing.
- User-configurable keybindings, colors, fonts of any size, even screen
  layouts.
- WAV export with optional looping and fade out.

## Notes

Ticket-style notes attached to a song (`Shift+F4`) for TODOs, descriptions,
sheet-music snippets and ideas — a home for the scribbles that would otherwise
end up in scattered text files and on paper, kept linked to where they matter.
Each note can point at the exact spot it's about (a pattern cell, an order
position or a sample) and **Go To** jumps you there. Notes carry a status
(`open`/`todo`/`fix`/`wip`/`done`/`old`/`info`) and live in a sidecar
`<module>.json`, so they never ship inside the module itself unless you share
that file too.

## Supported formats

- **MOD** — loads and saves Amiga ProTracker modules (including load support for
  15-sample Ultimate SoundTracker mods, NoiseTracker, and PowerPacked files).
- **P61A** — imports The Player 6.1a crunched modules.
- **IT and S3M** — imports Impulse Tracker and Scream Tracker 3 modules
  (including tempo/speed from the file headers).
- **Samples** — raw, IFF 8SVX, WAV, MP3 & Ogg Vorbis (MP3/Ogg require BASS).

![Sample Editor screenshot](https://github.com/hukkax/Propulse/blob/trunk/docs/images/ss2.png)

![Settings screen screenshot](https://github.com/hukkax/Propulse/blob/trunk/docs/images/ss3.png)

## Building & contributing

Prebuilt binaries are currently produced for macOS (ARM64) and Windows x64.

If you want to build from source, contribute changes, or cut a release, see the
[Contributing guide](CONTRIBUTING.md).
