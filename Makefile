# Makefile for Propulse Tracker - Cross-platform build support
# Requires: FreePascal Compiler (fpc) 3.2+
# Usage: 
#   make [TARGET=<target>] [MODE=release|debug]
#   make help-targets  # List all available targets
#
# Examples:
#   make TARGET=macos-arm64 release
#   make TARGET=windows-x64 release
#   make TARGET=linux-x64 release
#   make all-targets  # Build all targets

# Project configuration
PROJECT_NAME = Propulse
SRC_DIR = src
OUTPUT_DIR = .
BIN_DIR = bin

# Detect host platform
HOST_OS := $(shell uname -s | tr '[:upper:]' '[:lower:]')
HOST_ARCH := $(shell uname -m)

# Default target (host platform)
ifeq ($(HOST_OS),darwin)
  ifeq ($(HOST_ARCH),arm64)
    DEFAULT_TARGET = macos-arm64
  else
    DEFAULT_TARGET = macos-x86
  endif
else ifeq ($(HOST_OS),linux)
  ifeq ($(HOST_ARCH),aarch64)
    DEFAULT_TARGET = linux-arm64
  else
    DEFAULT_TARGET = linux-x64
  endif
else
  DEFAULT_TARGET = windows-x64
endif

# Target selection
TARGET ?= $(DEFAULT_TARGET)
MODE ?= release

# Parse target into OS and CPU
ifeq ($(TARGET),macos-arm64)
  TARGET_CPU = aarch64
  TARGET_OS = darwin
  BINARY_EXT =
  UNIT_OUTPUT_DIR = $(SRC_DIR)/lib/aarch64-darwin
  PLATFORM_DEFINES = -dCPUAARCH64 -dTARGET_ARM64 -dUSENATIVECODE -dENABLE_SOXR
  LIB_DIR = lib/macos-arm64
  LIB_PATHS = -k-L$(LIB_DIR) -k-L/opt/homebrew/lib
  POST_BUILD = fix-dylib-paths
#else ifeq ($(TARGET),macos-x86)
#  TARGET_CPU = i386
#  TARGET_OS = darwin
#  BINARY_EXT =
#  UNIT_OUTPUT_DIR = $(SRC_DIR)/lib/i386-darwin
#  PLATFORM_DEFINES = -dCPUI386 -dTARGET_X86 -dUSENATIVECODE
#  LIB_DIR = lib/macos-x86
#  LIB_PATHS = -k-L$(LIB_DIR) -k-L/usr/local/lib
#  POST_BUILD =
else ifeq ($(TARGET),windows-x64)
  TARGET_CPU = x86_64
  TARGET_OS = win64
  BINARY_EXT = .exe
  UNIT_OUTPUT_DIR = $(SRC_DIR)/lib/x86_64-win64
  PLATFORM_DEFINES = -dCPUX86_64 -dTARGET_X64 -dWINDOWS
  LIB_DIR = lib/windows-x64
  LIB_PATHS = -k-L$(LIB_DIR)
  POST_BUILD =
#else ifeq ($(TARGET),linux-x64)
#  TARGET_CPU = x86_64
#  TARGET_OS = linux
#  BINARY_EXT =
#  UNIT_OUTPUT_DIR = $(SRC_DIR)/lib/x86_64-linux
#  PLATFORM_DEFINES = -dCPUX86_64 -dTARGET_X64 -dLINUX
#  LIB_DIR = lib/linux-x64
#  LIB_PATHS = -k-L$(LIB_DIR) -k-L/usr/lib -k-L/usr/local/lib
#  POST_BUILD =
#else ifeq ($(TARGET),linux-arm64)
#  TARGET_CPU = aarch64
#  TARGET_OS = linux
#  BINARY_EXT =
#  UNIT_OUTPUT_DIR = $(SRC_DIR)/lib/aarch64-linux
#  PLATFORM_DEFINES = -dCPUAARCH64 -dTARGET_ARM64 -dLINUX
#  LIB_DIR = lib/linux-arm64
#  LIB_PATHS = -k-L$(LIB_DIR) -k-L/usr/lib -k-L/usr/local/lib
#  POST_BUILD =
else
  $(error Unknown target: $(TARGET). Use 'make help-targets' to see available targets)
endif

# Detect if we're cross-compiling
IS_CROSS_COMPILE = 0
USE_CROSS_COMPILER = 0
ifeq ($(TARGET_OS),win64)
  ifneq ($(HOST_OS),windows)
    IS_CROSS_COMPILE = 1
  endif
else ifeq ($(TARGET_OS),linux)
  ifneq ($(HOST_OS),linux)
    IS_CROSS_COMPILE = 1
  endif
else ifeq ($(TARGET_OS),darwin)
  ifneq ($(HOST_OS),darwin)
    IS_CROSS_COMPILE = 1
  endif
endif

# Select compiler based on target
ifeq ($(IS_CROSS_COMPILE),1)
  # Cross-compilation: use cross-compiler binaries
  ifeq ($(TARGET_OS),win64)
    ifeq ($(TARGET_CPU),x86_64)
      # For Windows x64, try in order:
      # 1. ppcrossx64 (dedicated Windows cross-compiler, includes RTL)
      # 2. ppcx64 -Twin64 (generic x86_64 compiler targeting Windows, needs RTL)
      # 3. fpc -Twin64 -Px86_64 (fallback, needs RTL)
      
      # Search for ppcrossx64 in multiple locations
      # Check PATH first, then fpcupdeluxe installation directories, then FPC lib directories
      CROSS_COMPILER := $(shell which ppcrossx64 2>/dev/null | head -1)
      ifeq ($(CROSS_COMPILER),)
        # Check fpcupdeluxe typical installation locations (multiple possible base dirs)
        FPCUPDELUXE_BASES := $(shell ls -d ~/fpcupdeluxe ~/fpcupdeluxe/fpc ~/Applications/fpcupdeluxe/fpc 2>/dev/null)
        ifneq ($(FPCUPDELUXE_BASES),)
          CROSS_COMPILER := $(shell find $(FPCUPDELUXE_BASES) -name "ppcrossx64" -type f 2>/dev/null | head -1)
        endif
      endif
      ifeq ($(CROSS_COMPILER),)
        # Check FPC lib directories
        FPC_VERSION := $(shell fpc -iV 2>/dev/null)
        CROSS_COMPILER := $(shell find /usr/local/lib/fpc/$(FPC_VERSION) -name "ppcrossx64" -type f 2>/dev/null | head -1)
      endif
      ifeq ($(CROSS_COMPILER),)
        # Last resort: search common fpcupdeluxe installation patterns
        CROSS_COMPILER := $(shell find ~ -maxdepth 5 -path "*/fpcupdeluxe/*/fpc/bin/*/ppcrossx64" -type f 2>/dev/null | head -1)
      endif
      
      ifneq ($(CROSS_COMPILER),)
        FPC = $(CROSS_COMPILER)
        USE_CROSS_COMPILER = 1
      else
        # Try ppcx64 (generic x86_64 compiler that can target Windows)
        GENERIC_X64_COMPILER := $(shell which ppcx64 2>/dev/null | head -1)
        ifneq ($(GENERIC_X64_COMPILER),)
          FPC = $(GENERIC_X64_COMPILER)
          USE_CROSS_COMPILER = 0
          # We'll add -Twin64 in the flags
        else
          # Fall back to fpc with explicit target flags (requires Windows RTL units)
          FPC = fpc
          USE_CROSS_COMPILER = 0
        endif
        # Check if Windows RTL units are available
        # Note: ppcx64 can target Windows with -Twin64, but still needs Windows RTL units
        FPC_VERSION := $(shell fpc -iV 2>/dev/null)
        # Check multiple locations for Windows RTL units
        WIN64_RTL_PATH := $(shell find /usr/local/lib/fpc/$(FPC_VERSION)/units -type d -name "x86_64-win64" 2>/dev/null | head -1)
        ifeq ($(WIN64_RTL_PATH),)
          # Check fpcupdeluxe installation directories (multiple possible locations)
          FPCUPDELUXE_BASES := $(shell ls -d ~/fpcupdeluxe ~/fpcupdeluxe/fpc ~/Applications/fpcupdeluxe/fpc 2>/dev/null)
          ifneq ($(FPCUPDELUXE_BASES),)
            WIN64_RTL_PATH := $(shell find $(FPCUPDELUXE_BASES) -type d -name "x86_64-win64" 2>/dev/null | head -1)
          endif
        endif
        ifeq ($(WIN64_RTL_PATH),)
          # Last resort: search common fpcupdeluxe installation patterns
          WIN64_RTL_PATH := $(shell find ~ -maxdepth 6 -path "*/fpcupdeluxe/*/fpc/lib/fpc/*/units/x86_64-win64" -type d 2>/dev/null | head -1)
        endif
        ifeq ($(WIN64_RTL_PATH),)
          $(error Windows x64 RTL units not found. To cross-compile for Windows x64: \
You have ppcx64 which can target Windows, but Windows RTL units are required. Options: \
1. Install ppcrossx64 (includes Windows RTL units) using fpcupdeluxe: https://github.com/newpascal/fpcupdeluxe/releases \
2. Build Windows RTL units from FPC source (see bootstrap-mac.sh for commented example) \
3. Install Windows RTL units separately if available \
Note: If you installed via fpcupdeluxe, ensure the installation completed successfully.)
        endif
        # Store WIN64_RTL_PATH for use in unit paths
        WIN64_RTL_UNIT_PATH := $(WIN64_RTL_PATH)
      endif
    endif
  else ifeq ($(TARGET_OS),linux)
    ifeq ($(TARGET_CPU),x86_64)
      # For Linux x64, check if we're on macOS and need ppcrossx64, or use native compiler
      ifeq ($(HOST_OS),darwin)
        CROSS_COMPILER := $(shell which ppcrossx64 2>/dev/null | head -1)
        ifneq ($(CROSS_COMPILER),)
          FPC = $(CROSS_COMPILER)
          USE_CROSS_COMPILER = 1
        else
          FPC = fpc
          USE_CROSS_COMPILER = 0
        endif
      else
        FPC = fpc
        USE_CROSS_COMPILER = 0
      endif
    else ifeq ($(TARGET_CPU),aarch64)
      CROSS_COMPILER := $(shell which ppcrossa64 2>/dev/null | head -1)
      ifneq ($(CROSS_COMPILER),)
        FPC = $(CROSS_COMPILER)
        USE_CROSS_COMPILER = 1
      else
        FPC = fpc
        USE_CROSS_COMPILER = 0
      endif
    endif
  endif
else
  # Native compilation: use regular fpc
FPC = fpc
  USE_CROSS_COMPILER = 0
endif

# Unit search paths (relative to src directory)
UNIT_PATHS = \
	-Fu$(SRC_DIR)/protracker \
	-Fu$(SRC_DIR)/cwe \
	-Fu$(SRC_DIR)/cwe/widgets \
	-Fu$(SRC_DIR)/screen \
	-Fu$(SRC_DIR)/dialog \
	-Fu$(SRC_DIR)/include \
	-Fu$(SRC_DIR)/include/sdl2 \
	-Fu$(SRC_DIR)/include/bass \
	-Fu$(SRC_DIR)/include/generics.collections/src

# Add Windows RTL unit path if cross-compiling for Windows and RTL path was found
# Include all subdirectories to ensure all Windows RTL, FCL, and Windows-specific units are found
ifeq ($(TARGET_OS),win64)
  ifdef WIN64_RTL_UNIT_PATH
    # Add RTL unit paths
    UNIT_PATHS += -Fu$(WIN64_RTL_UNIT_PATH)/rtl -Fu$(WIN64_RTL_UNIT_PATH) -Fu$(WIN64_RTL_UNIT_PATH)/rtl-generics -Fu$(WIN64_RTL_UNIT_PATH)/rtl-objpas -Fu$(WIN64_RTL_UNIT_PATH)/rtl-win
    # Add FCL (Free Component Library) unit paths
    UNIT_PATHS += -Fu$(WIN64_RTL_UNIT_PATH)/fcl-base -Fu$(WIN64_RTL_UNIT_PATH)/fcl-extra -Fu$(WIN64_RTL_UNIT_PATH)/fcl-process -Fu$(WIN64_RTL_UNIT_PATH)/fcl-net
    # Add Windows-specific unit paths
    UNIT_PATHS += -Fu$(WIN64_RTL_UNIT_PATH)/winunits-base -Fu$(WIN64_RTL_UNIT_PATH)/winunits-extra
  endif
endif

# Compiler flags base
# When using dedicated cross-compilers (ppcross*), -T and -P are implicit
# When using fpc with -T/-P flags, we need to specify them explicitly
ifeq ($(IS_CROSS_COMPILE),1)
  ifeq ($(USE_CROSS_COMPILER),1)
    # Using dedicated cross-compiler (ppcrossx64, etc.) - no need for -T/-P
    FPC_FLAGS_BASE = \
	-Mdelphi \
	-Sc \
	-Cg \
	-Fi$(SRC_DIR) \
	-Fl$(SRC_DIR)/include/sdl2 \
	-Fl$(SRC_DIR)/include/bass \
	-FE$(BIN_DIR) \
	-FU$(UNIT_OUTPUT_DIR) \
	-Xd
  else
    # Using fpc with cross-compilation flags - need -T and -P
    FPC_FLAGS_BASE = \
	-T$(TARGET_OS) \
	-P$(TARGET_CPU) \
	-Mdelphi \
	-Sc \
	-Cg \
	-Fi$(SRC_DIR) \
	-Fl$(SRC_DIR)/include/sdl2 \
	-Fl$(SRC_DIR)/include/bass \
	-FE$(BIN_DIR) \
	-FU$(UNIT_OUTPUT_DIR) \
	-Xd
  endif
else
  # Native compilation
FPC_FLAGS_BASE = \
	-T$(TARGET_OS) \
	-P$(TARGET_CPU) \
	-Mdelphi \
	-Sc \
	-Cg \
	-Fi$(SRC_DIR) \
	-Fl$(SRC_DIR)/include/sdl2 \
	-Fl$(SRC_DIR)/include/bass \
	-FE$(BIN_DIR) \
	-FU$(UNIT_OUTPUT_DIR) \
	-Xd
endif

# Release mode flags
FPC_FLAGS_RELEASE = \
	$(FPC_FLAGS_BASE) \
	-O3 \
	-XX \
	-Xs \
	-dRELEASE \
	-dBASS_DYNAMIC \
	-dDISABLE_SDL2_2_0_5 \
	-dDISABLE_SDL2_2_0_4 \
	$(PLATFORM_DEFINES)

# Debug mode flags
FPC_FLAGS_DEBUG = \
	$(FPC_FLAGS_BASE) \
	-g \
	-gl \
	-gh \
	-Cr \
	-Ct \
	-Ci \
	-Co \
	-Sa \
	-dDEBUG \
	-dBASS_DYNAMIC \
	-dDISABLE_SDL2_2_0_5 \
	-dDISABLE_SDL2_2_0_4 \
	$(PLATFORM_DEFINES)

# Source files
MAIN_SOURCE = $(SRC_DIR)/propulse.pas
RESOURCE_FILE = $(SRC_DIR)/propulse.res

# Output binary names (output directly to BIN_DIR)
ifeq ($(MODE),debug)
  OUTPUT_BINARY = $(BIN_DIR)/$(PROJECT_NAME)-$(TARGET)-debug$(BINARY_EXT)
  FPC_FLAGS = $(FPC_FLAGS_DEBUG)
else
  OUTPUT_BINARY = $(BIN_DIR)/$(PROJECT_NAME)-$(TARGET)$(BINARY_EXT)
  FPC_FLAGS = $(FPC_FLAGS_RELEASE)
endif

# Default target
all: $(MODE)

# Release build
release: $(OUTPUT_BINARY)
	@if [ -n "$(POST_BUILD)" ]; then \
		$(MAKE) $(POST_BUILD) BINARY=$(OUTPUT_BINARY); \
	fi

# Debug build
debug: $(OUTPUT_BINARY)
	@if [ -n "$(POST_BUILD)" ]; then \
		$(MAKE) $(POST_BUILD) BINARY=$(OUTPUT_BINARY); \
	fi

# Build binary
$(OUTPUT_BINARY): $(MAIN_SOURCE) $(RESOURCE_FILE)
	@echo "Building $(PROJECT_NAME) for $(TARGET) ($(MODE))..."
	@echo "  Target: $(TARGET_CPU)-$(TARGET_OS)"
	@mkdir -p $(UNIT_OUTPUT_DIR)
	@mkdir -p $(BIN_DIR)
	$(FPC) $(FPC_FLAGS) $(UNIT_PATHS) $(MAIN_SOURCE) -o$(OUTPUT_BINARY) \
		-k-lSDL2 -k-lbass -k-lsoxr $(LIB_PATHS)
	@echo "Build complete: $(OUTPUT_BINARY)"
	@if [ -d "$(LIB_DIR)" ]; then \
		echo "Copying libraries from $(LIB_DIR) to $(BIN_DIR)..."; \
		cp $(LIB_DIR)/* $(BIN_DIR)/ 2>/dev/null || true; \
	fi

# Fix dylib paths (macOS only)
# Automatically called for macOS builds via POST_BUILD
# Can also be called manually: make fix-dylib-paths BINARY=<path-to-binary>
fix-dylib-paths:
	@if [ -z "$(BINARY)" ]; then \
		echo "Error: BINARY variable not set"; \
		echo "Usage: make fix-dylib-paths BINARY=<path-to-binary>"; \
		exit 1; \
	fi
	@if [ ! -f "$(BINARY)" ]; then \
		echo "Error: Binary $(BINARY) not found"; \
		exit 1; \
	fi
	@echo "Fixing dylib paths in $(BINARY)..."
	@SDL2_PATH=$$(otool -L "$(BINARY)" 2>/dev/null | grep -i "libSDL2" | head -1 | awk '{print $$1}' | tr -d ' '); \
	BASS_PATH=$$(otool -L "$(BINARY)" 2>/dev/null | grep -i "libbass" | head -1 | awk '{print $$1}' | tr -d ' '); \
	SOXR_PATH=$$(otool -L "$(BINARY)" 2>/dev/null | grep -i "libsoxr" | head -1 | awk '{print $$1}' | tr -d ' '); \
	if [ -n "$$SDL2_PATH" ] && [ "$$SDL2_PATH" != "@executable_path/libSDL2.dylib" ]; then \
		echo "  Changing SDL2 path: $$SDL2_PATH -> @executable_path/libSDL2.dylib"; \
		install_name_tool -change "$$SDL2_PATH" "@executable_path/libSDL2.dylib" "$(BINARY)" || true; \
	fi; \
	if [ -n "$$BASS_PATH" ] && [ "$$BASS_PATH" != "@executable_path/libbass.dylib" ]; then \
		echo "  Changing BASS path: $$BASS_PATH -> @executable_path/libbass.dylib"; \
		install_name_tool -change "$$BASS_PATH" "@executable_path/libbass.dylib" "$(BINARY)" || true; \
	fi; \
	if [ -n "$$SOXR_PATH" ] && [ "$$SOXR_PATH" != "@executable_path/libsoxr.dylib" ]; then \
		echo "  Changing SOXR path: $$SOXR_PATH -> @executable_path/libsoxr.dylib"; \
		install_name_tool -change "$$SOXR_PATH" "@executable_path/libsoxr.dylib" "$(BINARY)" || true; \
	fi
	@echo "Dylib paths fixed."

# Build all targets
all-targets:
	@echo "Building all targets..."
	@$(MAKE) TARGET=macos-arm64 MODE=release
	@$(MAKE) TARGET=windows-x64 MODE=release
	#@$(MAKE) TARGET=macos-x86 MODE=release
	#@$(MAKE) TARGET=linux-x64 MODE=release
	#@$(MAKE) TARGET=linux-arm64 MODE=release
	@echo "All targets built!"

# Build all targets (debug)
all-targets-debug:
	@echo "Building all targets (debug)..."
	@$(MAKE) TARGET=macos-arm64 MODE=debug
	@$(MAKE) TARGET=windows-x64 MODE=debug
	#@$(MAKE) TARGET=macos-x86 MODE=debug
	#@$(MAKE) TARGET=linux-x64 MODE=debug
	#@$(MAKE) TARGET=linux-arm64 MODE=debug
	@echo "All targets built (debug)!"

# Clean build artifacts for current target
clean:
	@echo "Cleaning build artifacts for $(TARGET)..."
	rm -rf $(UNIT_OUTPUT_DIR)
	rm -f $(BIN_DIR)/$(PROJECT_NAME)-$(TARGET)*
	rm -f $(BIN_DIR)/*.dylib $(BIN_DIR)/*.dll $(BIN_DIR)/*.so 2>/dev/null || true
	rm -f $(OUTPUT_DIR)/*.o
	rm -f $(OUTPUT_DIR)/*.ppu
	@echo "Clean complete."

# Clean everything including compiled units
distclean: clean-all-targets
	@echo "Cleaning all compiled units..."
	find $(SRC_DIR) -name "*.o" -delete
	find $(SRC_DIR) -name "*.ppu" -delete
	find $(SRC_DIR) -name "*.compiled" -delete
	@echo "Distclean complete."

# Clean all targets
clean-all-targets:
	@echo "Cleaning all targets..."
	@$(MAKE) TARGET=macos-arm64 clean
	@$(MAKE) TARGET=windows-x64 clean
	#@$(MAKE) TARGET=macos-x86 clean
	#@$(MAKE) TARGET=linux-x64 clean
	#@$(MAKE) TARGET=linux-arm64 clean
	@echo "All targets cleaned."

# Help target
help:
	@echo "Propulse Tracker Makefile - Cross-platform build support"
	@echo ""
	@echo "Usage:"
	@echo "  make [TARGET=<target>] [MODE=release|debug]"
	@echo ""
	@echo "Examples:"
	@echo "  make                          # Build for host platform (release)"
	@echo "  make TARGET=macos-arm64       # Build for macOS ARM64"
	@echo "  make TARGET=windows-x64 release  # Build for Windows x64"
	@#echo "  make TARGET=linux-x64 debug   # Build debug for Linux x64"
	@echo "  make all-targets              # Build all targets"
	@echo "  make all-targets-debug        # Build all targets (debug)"
	@echo ""
	@echo "Available targets:"
	@echo "  macos-arm64    - macOS ARM64 (Apple Silicon)"
	@echo "  windows-x64    - Windows 64-bit"
	@#echo "  macos-x86      - macOS x86 (Intel)"
	@#echo "  linux-x64      - Linux x86_64"
	@#echo "  linux-arm64    - Linux ARM64"
	@echo ""
	@echo "Other commands:"
	@echo "  make clean                    # Clean current target"
	@echo "  make clean-all-targets        # Clean all targets"
	@echo "  make distclean                # Clean everything"
	@echo "  make help-targets             # List all targets"
	@echo "  make fix-dylib-paths BINARY=<path>  # Fix dylib paths (macOS only, manual)"
	@echo ""
	@echo "Packaging commands:"
	@echo "  make package-windows-x64      # Create Windows x64 ZIP package"
	@echo "  make package-macos-arm64      # Create macOS ARM64 ZIP package"
	@#echo "  make package-macos-x86        # Create macOS x86 ZIP package"
	@echo "  make package-all-targets      # Package all targets"
	@echo ""
	@echo "Requirements:"
	@echo "  - FreePascal Compiler (fpc) 3.2+"
	@echo "  - Cross-compilers may be needed for some targets"
	@echo "  - SDL2 library"
	@echo "  - BASS library"
	@echo ""
	@echo "Cross-compilation notes:"
	@echo "  - FPC supports cross-compilation using -P and -T flags"
	@echo "  - For Windows targets, you may need ppcrossx64"
	@echo "  - For Linux targets, you may need ppcrossx64/ppcrossa64"
	@echo "  - Cross-compilers can be installed via fpcupdeluxe or manually"
	@echo ""
	@echo "Current host: $(HOST_OS)-$(HOST_ARCH)"
	@echo "Default target: $(DEFAULT_TARGET)"

# List all targets
help-targets:
	@echo "Available build targets:"
	@echo "  macos-arm64    - macOS ARM64 (Apple Silicon)"
	@echo "  windows-x64    - Windows 64-bit"
	@#echo "  macos-x86      - macOS x86 (Intel)"
	@#echo "  linux-x64      - Linux x86_64"
	@#echo "  linux-arm64    - Linux ARM64"

# Packaging targets
# Note: PACKAGE_NAME is set per-target below to avoid variable expansion issues

# Package for Windows
package-windows-x64: $(BIN_DIR)/$(PROJECT_NAME)-windows-x64.exe
	@echo "Packaging $(PROJECT_NAME) for Windows x64..."
	@PACKAGE_DIR="$(BIN_DIR)/package-windows-x64"; \
	PACKAGE_NAME="$(PROJECT_NAME)-windows-x64"; \
	if [ ! -f "$(BIN_DIR)/$(PROJECT_NAME)-windows-x64.exe" ]; then \
		echo "Error: Binary not found. Build it first with: make TARGET=windows-x64 release"; \
		exit 1; \
	fi; \
	rm -rf $$PACKAGE_DIR; \
	mkdir -p $$PACKAGE_DIR/$$PACKAGE_NAME; \
	mkdir -p $$PACKAGE_DIR/$$PACKAGE_NAME/data; \
	echo "  Copying binary..."; \
	cp $(BIN_DIR)/$(PROJECT_NAME)-windows-x64.exe $$PACKAGE_DIR/$$PACKAGE_NAME/Propulse.exe; \
	echo "  Copying DLLs..."; \
	DLLS_MISSING=0; \
	if [ ! -f "$(BIN_DIR)/bass.dll" ]; then \
		echo "  Warning: bass.dll not found in $(BIN_DIR). Download Windows x64 version from https://www.un4seen.com/"; \
		DLLS_MISSING=1; \
	else \
		cp $(BIN_DIR)/bass.dll $$PACKAGE_DIR/$$PACKAGE_NAME/; \
		echo "  ✓ bass.dll"; \
	fi; \
	if [ ! -f "$(BIN_DIR)/SDL2.dll" ]; then \
		echo "  Warning: SDL2.dll not found in $(BIN_DIR). Download Windows x64 version from https://www.libsdl.org/"; \
		DLLS_MISSING=1; \
	else \
		cp $(BIN_DIR)/SDL2.dll $$PACKAGE_DIR/$$PACKAGE_NAME/; \
		echo "  ✓ SDL2.dll"; \
	fi; \
	if [ -f "$(BIN_DIR)/libsoxr.dll" ]; then \
		cp $(BIN_DIR)/libsoxr.dll $$PACKAGE_DIR/$$PACKAGE_NAME/; \
		echo "  ✓ libsoxr.dll"; \
	fi; \
	if [ $$DLLS_MISSING -eq 1 ]; then \
		echo "  Note: Package will be created but may be incomplete without DLLs."; \
	fi; \
	echo "  Copying data files..."; \
	cp -r data/* $$PACKAGE_DIR/$$PACKAGE_NAME/data/ 2>/dev/null || true; \
	if [ -f "license.txt" ]; then \
		cp license.txt $$PACKAGE_DIR/$$PACKAGE_NAME/; \
	fi; \
	echo "  Creating ZIP archive..."; \
	mkdir -p $(BIN_DIR); \
	ZIP_FILE="$$(cd $(BIN_DIR) && pwd)/$$PACKAGE_NAME.zip"; \
	cd $$PACKAGE_DIR && zip -q -r "$$ZIP_FILE" $$PACKAGE_NAME 2>&1 || (echo "Error: zip command failed. Is zip installed?" && rm -rf $$PACKAGE_DIR && exit 1); \
	rm -rf $$PACKAGE_DIR; \
	echo "Package created: $$ZIP_FILE"

# Package for macOS
package-macos-arm64: $(BIN_DIR)/$(PROJECT_NAME)-macos-arm64
	@echo "Packaging $(PROJECT_NAME) for macOS ARM64..."
	@PACKAGE_DIR="$(BIN_DIR)/package-macos-arm64"; \
	PACKAGE_NAME="$(PROJECT_NAME)-macos-arm64"; \
	if [ ! -f "$(BIN_DIR)/$(PROJECT_NAME)-macos-arm64" ]; then \
		echo "Error: Binary not found. Build it first with: make TARGET=macos-arm64 release"; \
		exit 1; \
	fi; \
	rm -rf $$PACKAGE_DIR; \
	mkdir -p $$PACKAGE_DIR/$$PACKAGE_NAME; \
	mkdir -p $$PACKAGE_DIR/$$PACKAGE_NAME/data; \
	echo "  Copying binary..."; \
	cp $(BIN_DIR)/$(PROJECT_NAME)-macos-arm64 $$PACKAGE_DIR/$$PACKAGE_NAME/Propulse; \
	chmod +x $$PACKAGE_DIR/$$PACKAGE_NAME/Propulse; \
	echo "  Copying dylibs..."; \
	DYLIBS_MISSING=0; \
	if [ ! -f "$(BIN_DIR)/libbass.dylib" ]; then \
		echo "  Warning: libbass.dylib not found in $(BIN_DIR). Download macOS ARM64 version from https://www.un4seen.com/"; \
		DYLIBS_MISSING=1; \
	else \
		cp $(BIN_DIR)/libbass.dylib $$PACKAGE_DIR/$$PACKAGE_NAME/; \
		echo "  ✓ libbass.dylib"; \
	fi; \
	if [ ! -f "$(BIN_DIR)/libSDL2.dylib" ]; then \
		echo "  Warning: libSDL2.dylib not found in $(BIN_DIR). Install via: brew install sdl2, then copy from /opt/homebrew/lib/"; \
		DYLIBS_MISSING=1; \
	else \
		cp $(BIN_DIR)/libSDL2.dylib $$PACKAGE_DIR/$$PACKAGE_NAME/; \
		echo "  ✓ libSDL2.dylib"; \
	fi; \
	if [ -f "$(BIN_DIR)/libsoxr.dylib" ]; then \
		cp $(BIN_DIR)/libsoxr.dylib $$PACKAGE_DIR/$$PACKAGE_NAME/; \
		echo "  ✓ libsoxr.dylib"; \
	fi; \
	if [ $$DYLIBS_MISSING -eq 1 ]; then \
		echo "  Note: Package will be created but may be incomplete without dylibs."; \
	fi; \
	echo "  Fixing dylib paths..."; \
	BINARY_PATH="$$PACKAGE_DIR/$$PACKAGE_NAME/Propulse"; \
	$(MAKE) fix-dylib-paths BINARY="$$BINARY_PATH"; \
	echo "  Copying data files..."; \
	cp -r data/* $$PACKAGE_DIR/$$PACKAGE_NAME/data/ 2>/dev/null || true; \
	if [ -f "license.txt" ]; then \
		cp license.txt $$PACKAGE_DIR/$$PACKAGE_NAME/; \
	fi; \
	echo "  Creating ZIP archive..."; \
	mkdir -p $(BIN_DIR); \
	ZIP_FILE="$$(cd $(BIN_DIR) && pwd)/$$PACKAGE_NAME.zip"; \
	cd $$PACKAGE_DIR && zip -q -r "$$ZIP_FILE" $$PACKAGE_NAME 2>&1 || (echo "Error: zip command failed. Is zip installed?" && rm -rf $$PACKAGE_DIR && exit 1); \
	rm -rf $$PACKAGE_DIR; \
	echo "Package created: $$ZIP_FILE"

#package-macos-x86: $(BIN_DIR)/$(PROJECT_NAME)-macos-x86
#	@echo "Packaging $(PROJECT_NAME) for macOS x86..."
#	@PACKAGE_DIR="$(BIN_DIR)/package-macos-x86"; \
#	PACKAGE_NAME="$(PROJECT_NAME)-macos-x86"; \
#	if [ ! -f "$(BIN_DIR)/$(PROJECT_NAME)-macos-x86" ]; then \
#		echo "Error: Binary not found. Build it first with: make TARGET=macos-x86 release"; \
#		exit 1; \
#	fi; \
#	rm -rf $$PACKAGE_DIR; \
#	mkdir -p $$PACKAGE_DIR/$$PACKAGE_NAME; \
#	mkdir -p $$PACKAGE_DIR/$$PACKAGE_NAME/data; \
#	echo "  Copying binary..."; \
#	cp $(BIN_DIR)/$(PROJECT_NAME)-macos-x86 $$PACKAGE_DIR/$$PACKAGE_NAME/Propulse; \
#	chmod +x $$PACKAGE_DIR/$$PACKAGE_NAME/Propulse; \
#	echo "  Copying dylibs..."; \
#	DYLIBS_MISSING=0; \
#	if [ ! -f "$(BIN_DIR)/libbass.dylib" ]; then \
#		echo "  Warning: libbass.dylib not found in $(BIN_DIR). Download macOS x86 version from https://www.un4seen.com/"; \
#		DYLIBS_MISSING=1; \
#	else \
#		cp $(BIN_DIR)/libbass.dylib $$PACKAGE_DIR/$$PACKAGE_NAME/; \
#		echo "  ✓ libbass.dylib"; \
#	fi; \
#	if [ ! -f "$(BIN_DIR)/libSDL2.dylib" ]; then \
#		echo "  Warning: libSDL2.dylib not found in $(BIN_DIR). Install via: brew install sdl2, then copy from /usr/local/lib/"; \
#		DYLIBS_MISSING=1; \
#	else \
#		cp $(BIN_DIR)/libSDL2.dylib $$PACKAGE_DIR/$$PACKAGE_NAME/; \
#		echo "  ✓ libSDL2.dylib"; \
#	fi; \
#	if [ -f "$(BIN_DIR)/libsoxr.dylib" ]; then \
#		cp $(BIN_DIR)/libsoxr.dylib $$PACKAGE_DIR/$$PACKAGE_NAME/; \
#		echo "  ✓ libsoxr.dylib"; \
#	fi; \
#	if [ $$DYLIBS_MISSING -eq 1 ]; then \
#		echo "  Note: Package will be created but may be incomplete without dylibs."; \
#	fi; \
#	echo "  Fixing dylib paths..."; \
#	BINARY_PATH="$$PACKAGE_DIR/$$PACKAGE_NAME/Propulse"; \
#	$(MAKE) fix-dylib-paths BINARY="$$BINARY_PATH"; \
#	echo "  Copying data files..."; \
#	cp -r data/* $$PACKAGE_DIR/$$PACKAGE_NAME/data/ 2>/dev/null || true; \
#	if [ -f "license.txt" ]; then \
#		cp license.txt $$PACKAGE_DIR/$$PACKAGE_NAME/; \
#	fi; \
#	echo "  Creating ZIP archive..."; \
#	mkdir -p $(BIN_DIR); \
#	ZIP_FILE="$$(cd $(BIN_DIR) && pwd)/$$PACKAGE_NAME.zip"; \
#	cd $$PACKAGE_DIR && zip -q -r "$$ZIP_FILE" $$PACKAGE_NAME 2>&1 || (echo "Error: zip command failed. Is zip installed?" && rm -rf $$PACKAGE_DIR && exit 1); \
#	rm -rf $$PACKAGE_DIR; \
#	echo "Package created: $$ZIP_FILE"

# Package all targets
package-all-targets:
	@echo "Packaging all targets..."
	@$(MAKE) package-windows-x64
	@$(MAKE) package-macos-arm64
	#@$(MAKE) package-macos-x86
	@echo "All targets packaged!"

.PHONY: all release debug clean distclean clean-all-targets all-targets all-targets-debug help help-targets fix-dylib-paths package-windows-x64 package-macos-arm64 package-all-targets
#package-macos-x86
