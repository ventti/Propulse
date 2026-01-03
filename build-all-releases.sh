#!/bin/bash
set -e

# Clean build and release directories
rm -rf build
rm -rf release

# Clean FPC unit output cache.
# CMake presets build multiple configurations/targets, and reusing stale .ppu/.o
# across different compiler flags can trigger FPC internal errors.
rm -rf src/lib/aarch64-darwin
rm -rf src/lib/x86_64-darwin
rm -rf src/lib/x86_64-linux
rm -rf src/lib/x86_64-win64

python3 ./tools/scripts/validate_help.py

# Get workflow presets (they cover configure + build + package)
PRESETS=$(cmake --list-presets=workflow 2>&1 | grep -E '^\s+"[^"]+"' | sed 's/.*"\([^"]*\)".*/\1/')

# Test each workflow preset
for PRESET in $PRESETS; do
    cmake --workflow --preset "$PRESET"
done

# Write git describe version next to the packaged .zip files
VERSION=$(git describe --always --tags --dirty 2>/dev/null || echo unknown)
mkdir -p release
printf "%s\n" "${VERSION}" > release/version.txt

ln -s build/macos-arm64-release/Propulse-macos-arm64 ./Propulse || true