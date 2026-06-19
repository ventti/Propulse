#!/bin/bash
set -e

# Clean build and release directories
rm -rf build
rm -rf release

clean_fpc_units() {
    # CMake presets reuse a per-platform unit dir (src/lib/<cpu-os>) for BOTH
    # release and debug builds. Reusing .ppu/.o built with different compiler
    # flags across configurations triggers FPC internal errors, so wipe them.
    rm -rf src/lib/aarch64-darwin
    rm -rf src/lib/x86_64-darwin
    rm -rf src/lib/x86_64-linux
    rm -rf src/lib/x86_64-win64
}

clean_fpc_units

python3 ./tools/scripts/validate_help.py

# Get workflow presets (they cover configure + build + package)
PRESETS=$(cmake --list-presets=workflow 2>&1 | grep -E '^\s+"[^"]+"' | sed 's/.*"\([^"]*\)".*/\1/')

# Test each workflow preset
for PRESET in $PRESETS; do
    # Clean the shared unit cache before every preset: release/debug of the
    # same platform share src/lib/<cpu-os>, and mixing differently-compiled
    # .ppu causes FPC internal errors.
    clean_fpc_units
    cmake --workflow --preset "$PRESET"
done

# Write git describe version next to the packaged .zip files
VERSION=$(git describe --always --tags --dirty 2>/dev/null || echo unknown)
mkdir -p release
printf "%s\n" "${VERSION}" > release/version.txt

ln -s build/macos-arm64-release/Propulse-macos-arm64 ./Propulse || true