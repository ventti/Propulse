#!/bin/bash
# Bootstrap script for Propulse Tracker on macOS (ARM64)
# This script installs all necessary build tools and dependencies
#
# IMPORTANT: Keep it simple! Avoid overengineering.
# - Use simple error handling: if ! command; then error && exit 1; fi
# - Don't add unnecessary validation or complex logic
# - Fail fast and clearly

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "[${BLUE}INFO${NC}] $1"; }
success() { echo -e "[${GREEN}SUCCESS${NC}] $1"; }
warning() { echo -e "[${YELLOW}WARNING${NC}] $1"; }
error() { echo -e "[${RED}ERROR${NC}] $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Platform check
[[ "$(uname)" == "Darwin" ]] || error "This script is for macOS only."

# Check prerequisites
command -v brew >/dev/null || error "Homebrew not installed. Install from: https://brew.sh"
command -v xcode-select >/dev/null || error "Xcode command-line tools not installed. Install from: https://developer.apple.com/xcode/"

# Check FreePascal
if ! command -v fpc >/dev/null; then
    echo -e "${RED}ERROR${NC} FreePascal not found. Install using fpcupdeluxe:" >&2
    echo "  Run: ./install-fpcup-mac.sh" >&2
    exit 1
fi

FPC_VERSION=$(fpc -iV)
success "FreePascal version: $FPC_VERSION"

# Check Windows cross-compilation support (informational only)
if command -v ppcrossx64 >/dev/null; then
    info "ppcrossx64 (Windows x64 cross-compiler) found - Windows cross-compilation ready"
elif command -v ppcx64 >/dev/null; then
    warning "ppcx64 found (can target Windows with -Twin64), but Windows RTL units are required."
    info "To enable Windows cross-compilation, install Windows RTL units:"
    info "  Run: ./install-fpcup-mac.sh"
fi

# Summary
success "Bootstrap completed!"
info "Next: make TARGET=macos-arm64 release"

