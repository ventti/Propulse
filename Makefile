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
  PLATFORM_DEFINES = -dCPUAARCH64 -dTARGET_ARM64 -dUSENATIVECODE -dENABLE_SOXR -dENABLE_SOXR_FORCED
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

# Cross-compilation configuration mapping table
# Format: TARGET_OS-TARGET_CPU = cross_compiler_name,fallback_compiler,rtl_unit_dir,requires_host_check
# Empty values mean: use native compiler, no RTL needed, no host check
define CROSS_COMPILE_CONFIG
win64-x86_64 = ppcrossx64,ppcx64,x86_64-win64,
linux-x86_64 = ppcrossx64,,,darwin
linux-aarch64 = ppcrossa64,,,
endef

# Helper: Search for cross-compiler in common locations
# Usage: $(call find_cross_compiler,compiler_name)
find_cross_compiler = $(shell \
  which $(1) 2>/dev/null | head -1 || \
  find ~/fpcupdeluxe ~/fpcupdeluxe/fpc ~/Applications/fpcupdeluxe/fpc /usr/local/lib/fpc 2>/dev/null \
    -name "$(1)" -type f 2>/dev/null | head -1 || \
  find ~ -maxdepth 5 -path "*/fpcupdeluxe/*/fpc/bin/*/$(1)" -type f 2>/dev/null | head -1)

# Get HOME directory at Make parse time
HOME_DIR := $(shell echo $$HOME)

# Helper: Search for RTL units directory
# Usage: $(call find_rtl_path,unit_dir_name)
# Searches in standard FPC locations and fpcupdeluxe installations
find_rtl_path = $(shell \
  RESULT=$$(find /usr/local/lib/fpc/$$(fpc -iV 2>/dev/null)/units 2>/dev/null -type d -name "$(1)" 2>/dev/null | head -1); \
  if [ -z "$$RESULT" ]; then \
    RESULT=$$(find $(HOME_DIR)/Applications/fpcupdeluxe/fpc/units -type d -name "$(1)" 2>/dev/null | head -1); \
  fi; \
  if [ -z "$$RESULT" ]; then \
    RESULT=$$(find $(HOME_DIR)/fpcupdeluxe $(HOME_DIR)/fpcupdeluxe/fpc -type d -name "$(1)" 2>/dev/null | head -1); \
  fi; \
  if [ -z "$$RESULT" ]; then \
    RESULT=$$(find $(HOME_DIR) -maxdepth 6 -path "*/fpcupdeluxe/*/fpc/lib/fpc/*/units/$(1)" -type d 2>/dev/null | head -1); \
  fi; \
  if [ -z "$$RESULT" ]; then \
    RESULT=$$(find $(HOME_DIR) -maxdepth 6 -path "*/fpcupdeluxe/*/fpc/units/$(1)" -type d 2>/dev/null | head -1); \
  fi; \
  echo $$RESULT)

# Helper: Extract field from config entry (1=compiler, 2=fallback, 3=rtl, 4=host_check)
comma := ,
get_config_field = $(word $(2),$(subst $(comma), ,$(1)))

# Get configuration for current target
TARGET_KEY = $(TARGET_OS)-$(TARGET_CPU)
# Extract the config line: find line starting with TARGET_KEY, then get the value part after "="
# CROSS_COMPILE_CONFIG is a multi-line variable, need to preserve newlines for grep
TARGET_CONFIG = $(shell printf '%s\n' '$(CROSS_COMPILE_CONFIG)' | grep '^$(TARGET_KEY) =' | sed 's/^$(TARGET_KEY) =//')
CROSS_COMPILER_NAME = $(call get_config_field,$(TARGET_CONFIG),1)
FALLBACK_COMPILER = $(call get_config_field,$(TARGET_CONFIG),2)
RTL_UNIT_DIR = $(call get_config_field,$(TARGET_CONFIG),3)
REQUIRES_HOST_CHECK = $(call get_config_field,$(TARGET_CONFIG),4)

# Detect if we're cross-compiling
IS_CROSS_COMPILE = $(if $(and $(TARGET_CONFIG),$(filter-out $(TARGET_OS),$(HOST_OS))),1,0)

# Select compiler based on target configuration
USE_CROSS_COMPILER = 0
ifeq ($(IS_CROSS_COMPILE),1)
  # Cross-compilation: try dedicated cross-compiler first
  ifeq ($(REQUIRES_HOST_CHECK),darwin)
    # Only use cross-compiler if host is macOS
    ifeq ($(HOST_OS),darwin)
      CROSS_COMPILER := $(if $(CROSS_COMPILER_NAME),$(call find_cross_compiler,$(CROSS_COMPILER_NAME)))
      FPC = $(if $(CROSS_COMPILER),$(CROSS_COMPILER),fpc)
      USE_CROSS_COMPILER = $(if $(CROSS_COMPILER),1,0)
    else
      FPC = fpc
      USE_CROSS_COMPILER = 0
    endif
  else
    # Try cross-compiler, then fallback, then fpc
    CROSS_COMPILER := $(if $(CROSS_COMPILER_NAME),$(call find_cross_compiler,$(CROSS_COMPILER_NAME)))
    ifneq ($(CROSS_COMPILER),)
      FPC = $(CROSS_COMPILER)
      USE_CROSS_COMPILER = 1
    else ifneq ($(FALLBACK_COMPILER),)
      FALLBACK := $(shell which $(FALLBACK_COMPILER) 2>/dev/null | head -1)
      ifneq ($(FALLBACK),)
        FPC = $(FALLBACK)
        # Fallback compiler (like ppcx64) is still a cross-compiler, but may need explicit RTL paths
        USE_CROSS_COMPILER = 0
      else
        FPC = fpc
        USE_CROSS_COMPILER = 0
      endif
    else
      FPC = fpc
      USE_CROSS_COMPILER = 0
    endif
    
    # Check for RTL units if required and not using dedicated cross-compiler
    # This includes fallback compilers like ppcx64 which may need explicit RTL paths
    ifneq ($(RTL_UNIT_DIR),)
      ifeq ($(USE_CROSS_COMPILER),0)
        RTL_UNIT_DIR := $(strip $(RTL_UNIT_DIR))
        RTL_PATH := $(call find_rtl_path,$(RTL_UNIT_DIR))
        RTL_PATH := $(strip $(RTL_PATH))
        ifeq ($(RTL_PATH),)
          $(error $(TARGET_OS) $(TARGET_CPU) RTL units not found. To cross-compile: \
1. Install $(CROSS_COMPILER_NAME) (includes RTL units) using fpcupdeluxe: https://github.com/newpascal/fpcupdeluxe/releases \
2. Build RTL units from FPC source (see bootstrap-mac.sh for commented example) \
3. Install RTL units separately if available \
Note: If you installed via fpcupdeluxe, ensure the installation completed successfully. \
Current compiler: $(FPC))
        endif
        # Store RTL path in OS-specific variable for later use
        ifeq ($(TARGET_OS),win64)
          WIN64_RTL_UNIT_PATH := $(RTL_PATH)
        endif
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

# Add FCL JSON unit path for macOS builds
ifeq ($(TARGET_OS),darwin)
  # Try to find FCL JSON units in common FPC installation locations
  FCL_JSON_PATH := $(shell find /usr/local/lib/fpc -type d -name "fcl-json" 2>/dev/null | head -1)
  ifeq ($(FCL_JSON_PATH),)
    FCL_JSON_PATH := $(shell find /opt/homebrew/lib/fpc -type d -name "fcl-json" 2>/dev/null | head -1)
  endif
  ifneq ($(FCL_JSON_PATH),)
    UNIT_PATHS += -Fu$(FCL_JSON_PATH)
  else
    # Fallback: try common FPC installation paths
    ifeq ($(TARGET_CPU),aarch64)
      UNIT_PATHS += -Fu/usr/local/lib/fpc/3.2.2/units/aarch64-darwin/fcl-json
    else
      UNIT_PATHS += -Fu/usr/local/lib/fpc/3.2.2/units/x86_64-darwin/fcl-json
    endif
  endif
endif

# Add RTL unit paths if cross-compiling for Windows and RTL path was found
# Include all subdirectories to ensure all Windows RTL, FCL, and Windows-specific units are found
ifeq ($(TARGET_OS),win64)
  ifdef WIN64_RTL_UNIT_PATH
    # Add RTL unit paths
    UNIT_PATHS += -Fu$(WIN64_RTL_UNIT_PATH)/rtl -Fu$(WIN64_RTL_UNIT_PATH) -Fu$(WIN64_RTL_UNIT_PATH)/rtl-generics -Fu$(WIN64_RTL_UNIT_PATH)/rtl-objpas -Fu$(WIN64_RTL_UNIT_PATH)/rtl-win
    # Add FCL (Free Component Library) unit paths
    UNIT_PATHS += -Fu$(WIN64_RTL_UNIT_PATH)/fcl-base -Fu$(WIN64_RTL_UNIT_PATH)/fcl-extra -Fu$(WIN64_RTL_UNIT_PATH)/fcl-process -Fu$(WIN64_RTL_UNIT_PATH)/fcl-net -Fu$(WIN64_RTL_UNIT_PATH)/fcl-json
    # Add Windows-specific unit paths
    UNIT_PATHS += -Fu$(WIN64_RTL_UNIT_PATH)/winunits-base -Fu$(WIN64_RTL_UNIT_PATH)/winunits-extra
  endif
endif

# Compiler flags base
# Common flags for all compilation modes
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

# Add target flags only when not using dedicated cross-compiler
# (dedicated cross-compilers like ppcrossx64 have -T/-P implicit)
ifeq ($(IS_CROSS_COMPILE),1)
  ifeq ($(USE_CROSS_COMPILER),0)
    FPC_FLAGS_BASE += -T$(TARGET_OS) -P$(TARGET_CPU)
  endif
else
  # Native compilation always needs explicit target flags
  FPC_FLAGS_BASE += -T$(TARGET_OS) -P$(TARGET_CPU)
endif

# Common flags shared between release and debug modes
FPC_FLAGS_COMMON = \
	$(FPC_FLAGS_BASE) \
	-gl \
	-dBASS_DYNAMIC \
	-dDISABLE_SDL2_2_0_5 \
	-dDISABLE_SDL2_2_0_4 \
	$(PLATFORM_DEFINES)

# Release mode flags
FPC_FLAGS_RELEASE = \
	$(FPC_FLAGS_COMMON) \
	-O3 \
	-XX \
	-Xs \
	-gv \
	-dRELEASE

# Debug mode flags
# -g: Generate debug information
# -gl: Generate line info (needed for stack traces - includes lineinfo unit)
# -gw: Generate DWARF debug info (required for macOS symbolication with atos/dsymutil)
# -gs: Generate Stabs debug info (for non-macOS platforms)
# -gh: Generate heap trace
# -Cr: Range checking
# -Ct: Stack checking  
# -Ci: I/O checking
# -Co: Overflow checking
# -Sa: Assertions
FPC_FLAGS_DEBUG = \
	$(FPC_FLAGS_COMMON) \
	-g \
	-gh \
	-Cr \
	-Ct \
	-Ci \
	-Co \
	-Sa \
	-dDEBUG

# Add platform-specific debug format
# macOS: Use DWARF (-gw) for proper symbolication with atos/dsymutil
# Other platforms: Use Stabs (-gs) or let FPC choose
ifeq ($(TARGET_OS),darwin)
  FPC_FLAGS_DEBUG += -gw
else
  FPC_FLAGS_DEBUG += -gs
endif

# Source files
MAIN_SOURCE = $(SRC_DIR)/propulse.pas
RESOURCE_FILE = $(SRC_DIR)/propulse.res

# Find all Pascal source files for dependency tracking
# Make needs to know when any source file changes to trigger FPC
# FPC then handles incremental compilation via .ppu files
ALL_PAS_FILES = $(shell find $(SRC_DIR) -name "*.pas" -type f 2>/dev/null | sort)

# Output binary names (output directly to BIN_DIR)
ifeq ($(MODE),debug)
  OUTPUT_BINARY = $(BIN_DIR)/$(PROJECT_NAME)-$(TARGET)-debug$(BINARY_EXT)
  FPC_FLAGS = $(FPC_FLAGS_DEBUG)
else
  OUTPUT_BINARY = $(BIN_DIR)/$(PROJECT_NAME)-$(TARGET)$(BINARY_EXT)
  FPC_FLAGS = $(FPC_FLAGS_RELEASE)
endif

# Default target (builds current target in release mode)
all: release-target

# Release build for current target
release-target:
	@$(MAKE) MODE=release TARGET=$(TARGET) $(BIN_DIR)/$(PROJECT_NAME)-$(TARGET)$(BINARY_EXT)
	@if [ -n "$(POST_BUILD)" ]; then \
		$(MAKE) MODE=release TARGET=$(TARGET) $(POST_BUILD) BINARY=$(BIN_DIR)/$(PROJECT_NAME)-$(TARGET)$(BINARY_EXT); \
	fi

# Release build: build all targets and create packages
# Builds all targets (shows errors), then packages what was successfully built
release:
	@BUILD_FAILED=0; \
	$(MAKE) all-targets || BUILD_FAILED=1; \
	$(MAKE) package-all-targets; \
	if [ "$$BUILD_FAILED" = "1" ]; then \
		echo "Release build completed with errors - some targets failed to build"; \
		exit 1; \
	else \
		echo "Release build complete: all targets built and packaged!"; \
	fi

# Debug build for current target
debug-target:
	@$(MAKE) MODE=debug TARGET=$(TARGET) $(BIN_DIR)/$(PROJECT_NAME)-$(TARGET)-debug$(BINARY_EXT)
	@if [ -n "$(POST_BUILD)" ]; then \
		$(MAKE) MODE=debug TARGET=$(TARGET) $(POST_BUILD) BINARY=$(BIN_DIR)/$(PROJECT_NAME)-$(TARGET)-debug$(BINARY_EXT); \
	fi
	@if [ "$(TARGET_OS)" = "darwin" ]; then \
		echo "Generating dSYM for macOS symbolication..."; \
		dsymutil $(BIN_DIR)/$(PROJECT_NAME)-$(TARGET)-debug$(BINARY_EXT) 2>&1 | grep -v "warning:.*no debug symbols" || true; \
		echo "Note: FreePascal's DWARF output has limited location info for functions."; \
		echo "      Use ./symbolicate.sh for symbolication (uses nm fallback)."; \
	fi

# Debug build: build all targets (debug mode)
debug: all-targets-debug
	@echo "Debug build complete: all targets built!"

# Build binary
# Depend on all source files so Make detects changes and triggers rebuild
# FPC handles incremental compilation via .ppu files once triggered
$(OUTPUT_BINARY): $(MAIN_SOURCE) $(RESOURCE_FILE) $(ALL_PAS_FILES)
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
	@echo "Setting up data and docs directories..."
	@if [ ! -e "$(BIN_DIR)/data" ]; then \
		if [ -d "data" ]; then \
			ln -sf ../data $(BIN_DIR)/data || cp -r data $(BIN_DIR)/data; \
			echo "  Created data link/directory in $(BIN_DIR)"; \
		else \
			echo "  Warning: data directory not found in project root"; \
		fi; \
	fi
	@if [ ! -e "$(BIN_DIR)/docs" ]; then \
		if [ -d "docs" ]; then \
			ln -sf ../docs $(BIN_DIR)/docs || cp -r docs $(BIN_DIR)/docs; \
			echo "  Created docs link/directory in $(BIN_DIR)"; \
		else \
			echo "  Warning: docs directory not found in project root"; \
		fi; \
	fi

# Rebuild target: forces full rebuild by cleaning units first
rebuild: clean
	@$(MAKE) $(MODE) TARGET=$(TARGET)

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

# Individual target builds (can be built in parallel with -j)
build-macos-arm64-release:
	$(MAKE) TARGET=macos-arm64 release-target

build-windows-x64-release:
	$(MAKE) TARGET=windows-x64 release-target

#build-macos-x86-release:
#	$(MAKE) TARGET=macos-x86 MODE=release

#build-linux-x64-release:
#	$(MAKE) TARGET=linux-x64 MODE=release

#build-linux-arm64-release:
#	$(MAKE) TARGET=linux-arm64 MODE=release

# Build all targets (parallelizable with -j)
all-targets: build-macos-arm64-release build-windows-x64-release
	@echo "All targets built!"

# Individual target builds (debug, can be built in parallel with -j)
build-macos-arm64-debug:
	$(MAKE) TARGET=macos-arm64 debug-target

build-windows-x64-debug:
	$(MAKE) TARGET=windows-x64 debug-target

#build-macos-x86-debug:
#	$(MAKE) TARGET=macos-x86 MODE=debug

#build-linux-x64-debug:
#	$(MAKE) TARGET=linux-x64 MODE=debug

#build-linux-arm64-debug:
#	$(MAKE) TARGET=linux-arm64 MODE=debug

# Build all targets (debug, parallelizable with -j)
all-targets-debug: build-macos-arm64-debug build-windows-x64-debug
	@echo "All targets built (debug)!"

# Clean build artifacts for current target
clean:
	@echo "Cleaning build artifacts for $(TARGET)..."
	rm -rf $(UNIT_OUTPUT_DIR)
	rm -rf $(BIN_DIR)/$(PROJECT_NAME)-$(TARGET)*.dSYM
	rm -f $(BIN_DIR)/$(PROJECT_NAME)-$(TARGET)*
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
	@echo "  make TARGET=windows-x64 release-target  # Build for Windows x64"
	@echo "  make release                  # Build all targets and create packages"
	@echo "  make debug                    # Build all targets (debug mode)"
	@#echo "  make TARGET=linux-x64 debug-target   # Build debug for Linux x64"
	@echo "  make all-targets              # Build all targets"
	@echo "  make all-targets-debug        # Build all targets (debug)"
	@echo "  make package-all-targets      # Package all targets"
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
	@echo "  make rebuild                  # Force full rebuild (clean + build)"
	@echo "  make release-target           # Build current target (release)"
	@echo "  make debug-target             # Build current target (debug)"
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
package-windows-x64:
	@if [ ! -f "$(BIN_DIR)/$(PROJECT_NAME)-windows-x64.exe" ]; then \
		echo "Skipping Windows x64 package: binary not found. Build it first with: make TARGET=windows-x64 release-target"; \
		exit 0; \
	fi; \
	echo "Packaging $(PROJECT_NAME) for Windows x64..."; \
	PACKAGE_DIR="$(BIN_DIR)/package-windows-x64"; \
	PACKAGE_NAME="$(PROJECT_NAME)-windows-x64"; \
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
	mkdir -p release; \
	ZIP_FILE="$$(cd release && pwd)/$$PACKAGE_NAME.zip"; \
	cd $$PACKAGE_DIR && zip -q -r "$$ZIP_FILE" $$PACKAGE_NAME 2>&1 || (echo "Error: zip command failed. Is zip installed?" && rm -rf $$PACKAGE_DIR && exit 1); \
	rm -rf $$PACKAGE_DIR; \
	echo "Package created: $$ZIP_FILE"

# Package for macOS
package-macos-arm64:
	@if [ ! -f "$(BIN_DIR)/$(PROJECT_NAME)-macos-arm64" ]; then \
		echo "Skipping macOS ARM64 package: binary not found. Build it first with: make TARGET=macos-arm64 release-target"; \
		exit 0; \
	fi; \
	echo "Packaging $(PROJECT_NAME) for macOS ARM64..."; \
	PACKAGE_DIR="$(BIN_DIR)/package-macos-arm64"; \
	PACKAGE_NAME="$(PROJECT_NAME)-macos-arm64"; \
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
	mkdir -p release; \
	ZIP_FILE="$$(cd release && pwd)/$$PACKAGE_NAME.zip"; \
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

# Package all targets (parallelizable with -j)
# Only packages binaries that exist (skips missing ones)
package-all-targets: package-macos-arm64 package-windows-x64
	@echo "All available targets packaged!"

.PHONY: all release release-target debug debug-target rebuild clean distclean clean-all-targets all-targets all-targets-debug build-macos-arm64-release build-windows-x64-release build-macos-arm64-debug build-windows-x64-debug help help-targets fix-dylib-paths package-windows-x64 package-macos-arm64 package-all-targets
#package-macos-x86
