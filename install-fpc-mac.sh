#!/bin/bash
# Install FPC with cross-compilation support using fpcupdeluxe
# This script downloads and sets up fpcupdeluxe (precompiled GUI tool)
# which can install FPC and cross-compilers without requiring Lazarus
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

ARCH=$(uname -m)

# Check prerequisites
command -v xcode-select >/dev/null || error "Xcode command-line tools not installed. Install from: https://developer.apple.com/xcode/"

# Check if Xcode command-line tools are properly installed
if ! xcode-select -p &>/dev/null; then
    error "Xcode command-line tools not properly installed. Run: xcode-select --install"
fi

# Check for Homebrew
command -v brew >/dev/null || error "Homebrew not installed. Install from: https://brew.sh"

# Use fpcupdeluxe (precompiled, no compilation needed)
# Check if fpcupdeluxe is already installed
FPCUPDELUXE_APP=""

# Check for ARM64 version
if [[ -f "$HOME/Applications/fpcupdeluxe-aarch64-darwin-cocoa.app/Contents/MacOS/fpcupdeluxe-aarch64-darwin-cocoa" ]]; then
    FPCUPDELUXE_APP="$HOME/Applications/fpcupdeluxe-aarch64-darwin-cocoa.app"
elif [[ -f "/Applications/fpcupdeluxe-aarch64-darwin-cocoa.app/Contents/MacOS/fpcupdeluxe-aarch64-darwin-cocoa" ]]; then
    FPCUPDELUXE_APP="/Applications/fpcupdeluxe-aarch64-darwin-cocoa.app"
elif [[ -f "$SCRIPT_DIR/fpcupdeluxe/fpcupdeluxe-aarch64-darwin-cocoa.app/Contents/MacOS/fpcupdeluxe-aarch64-darwin-cocoa" ]]; then
    FPCUPDELUXE_APP="$SCRIPT_DIR/fpcupdeluxe/fpcupdeluxe-aarch64-darwin-cocoa.app"
fi

# Check for x86_64 version if not found
if [[ -z "$FPCUPDELUXE_APP" ]]; then
    if [[ -f "$HOME/Applications/fpcupdeluxe-x86_64-darwin-cocoa.app/Contents/MacOS/fpcupdeluxe-x86_64-darwin-cocoa" ]]; then
        FPCUPDELUXE_APP="$HOME/Applications/fpcupdeluxe-x86_64-darwin-cocoa.app"
    elif [[ -f "/Applications/fpcupdeluxe-x86_64-darwin-cocoa.app/Contents/MacOS/fpcupdeluxe-x86_64-darwin-cocoa" ]]; then
        FPCUPDELUXE_APP="/Applications/fpcupdeluxe-x86_64-darwin-cocoa.app"
    elif [[ -f "$SCRIPT_DIR/fpcupdeluxe/fpcupdeluxe-x86_64-darwin-cocoa.app/Contents/MacOS/fpcupdeluxe-x86_64-darwin-cocoa" ]]; then
        FPCUPDELUXE_APP="$SCRIPT_DIR/fpcupdeluxe/fpcupdeluxe-x86_64-darwin-cocoa.app"
    fi
fi

if [[ -z "$FPCUPDELUXE_APP" ]]; then
    info "fpcupdeluxe not found. Downloading..."
    
    # Get latest release version
    LATEST_VERSION=$(curl -s "https://api.github.com/repos/LongDirtyAnimAlf/fpcupdeluxe/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || echo "latest")
    
    # Determine download URL based on architecture
    if [[ "$ARCH" == "arm64" ]]; then
        FPCUPDELUXE_URL="https://github.com/LongDirtyAnimAlf/fpcupdeluxe/releases/download/${LATEST_VERSION}/fpcupdeluxe-aarch64-darwin-cocoa.zip"
        FPCUPDELUXE_ZIP="fpcupdeluxe-aarch64-darwin-cocoa.zip"
        FPCUPDELUXE_APP_NAME="fpcupdeluxe-aarch64-darwin-cocoa.app"
    else
        FPCUPDELUXE_URL="https://github.com/LongDirtyAnimAlf/fpcupdeluxe/releases/download/${LATEST_VERSION}/fpcupdeluxe-x86_64-darwin-cocoa.zip"
        FPCUPDELUXE_ZIP="fpcupdeluxe-x86_64-darwin-cocoa.zip"
        FPCUPDELUXE_APP_NAME="fpcupdeluxe-x86_64-darwin-cocoa.app"
    fi
    
    
    INSTALL_DIR="$HOME/Applications"
    mkdir -p "$INSTALL_DIR"
    
    TEMP_DIR=$(mktemp -d)
    ZIP_FILE="$TEMP_DIR/$FPCUPDELUXE_ZIP"
    
    info "Downloading fpcupdeluxe (version $LATEST_VERSION)..."
    if command -v curl >/dev/null; then
        curl -L -o "$ZIP_FILE" "$FPCUPDELUXE_URL" || error "Failed to download fpcupdeluxe"
    else
        error "curl required to download fpcupdeluxe"
    fi
    
    info "Installing fpcupdeluxe to ~/Applications/..."
    if command -v unzip >/dev/null; then
        unzip -q -o "$ZIP_FILE" -d "$INSTALL_DIR" || error "Failed to extract fpcupdeluxe"
    else
        error "unzip required to extract fpcupdeluxe"
    fi
    
    FPCUPDELUXE_APP="$INSTALL_DIR/$FPCUPDELUXE_APP_NAME"
    rm -rf "$TEMP_DIR"
    
    success "fpcupdeluxe installed to: ~/Applications/$FPCUPDELUXE_APP_NAME"
else
    info "fpcupdeluxe found at: $FPCUPDELUXE_APP"
fi

# Provide instructions for using fpcupdeluxe GUI
echo ""
info "================================================================================"
info "fpcupdeluxe Installation Instructions"
info "================================================================================"
echo ""
info "fpcupdeluxe is a GUI application. Follow these steps to install FPC with"
info "cross-compilation support:"
echo ""
info "1. Launch fpcupdeluxe:"
info "   open \"$FPCUPDELUXE_APP\""
echo ""
info "2. In fpcupdeluxe GUI:"
info "   - Select 'FPC' tab"
info "   - Set 'FPC version' to: 3.2.2 (or latest stable)"
info "   - Set 'Install directory' to: $HOME/fpcupdeluxe (or your preferred location)"
info "   - Check 'Cross-compiler' option"
info "   - Under 'Cross-compiler', select:"
info "     • Windows x64 (win64-x86_64)"
info "     • Linux x64 (linux-x86_64)"
info "     • Linux ARM64 (linux-aarch64)"
info "   - Click 'Install/Update FPC' button"
echo ""
info "3. Wait for installation to complete (this may take 10-30 minutes)"
echo ""
info "4. After installation, verify with:"
info "   fpc -iV"
info "   ppcrossx64 -iV  # Windows x64 cross-compiler"
echo ""

# Ask if user wants to launch fpcupdeluxe now
read -p "Launch fpcupdeluxe now? [Y/n] " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    info "Launching fpcupdeluxe..."
    open "$FPCUPDELUXE_APP" || error "Failed to launch fpcupdeluxe"
    echo ""
    success "fpcupdeluxe launched!"
    info "Follow the instructions above to install FPC and cross-compilers."
else
    info "You can launch fpcupdeluxe later with:"
    info "  open \"$FPCUPDELUXE_APP\""
fi

# Summary
echo ""
success "Setup completed!"
info ""
info "After installing FPC via fpcupdeluxe, you can build Propulse:"
info "  make TARGET=macos-arm64 release"
info "  make TARGET=windows-x64 release"
info "  make TARGET=linux-x64 release"
info "  make TARGET=linux-arm64 release"

