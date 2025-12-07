# CMake toolchain file for macOS ARM64 cross-compilation
# Usage: cmake --preset macos-arm64-release -DCMAKE_TOOLCHAIN_FILE=cmake/toolchains/macos-arm64.cmake

set(CMAKE_SYSTEM_NAME Darwin)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

# Platform-specific configuration
set(TARGET_PLATFORM "macos-arm64")
set(TARGET_CPU "aarch64")
set(TARGET_OS "darwin")
set(BINARY_EXT "")
set(UNIT_OUTPUT_SUBDIR "aarch64-darwin")
set(PLATFORM_DEFINES "-dCPUAARCH64;-dTARGET_ARM64;-dUSENATIVECODE;-dENABLE_SOXR;-dENABLE_SOXR_FORCED")
set(LIB_DIR_SUBDIR "macos-arm64")
set(LIB_PATHS_EXTRA "-k-L/opt/homebrew/lib")
set(POST_BUILD_SCRIPT "fix-dylib-paths")
set(DEBUG_FORMAT "-gw")  # DWARF for macOS

# RTL unit configuration for cross-compilation
set(RTL_SUFFIX "aarch64-darwin")
set(RTL_UNIT_SUBDIRS "rtl;rtl-generics;rtl-objpas;rtl-unix")
set(FCL_UNIT_SUBDIRS "fcl-base;fcl-extra;fcl-process;fcl-net;fcl-json")
set(RTL_PLATFORM_UNIT_SUBDIRS "")
set(RTL_PATH_SUFFIXES "units/${RTL_SUFFIX};lib/fpc/*/units/${RTL_SUFFIX};*/units/${RTL_SUFFIX}")
set(RTL_USE_LINUX_PATHS FALSE)
set(RTL_WARNING_PLATFORM "macOS")
set(RTL_CROSSCOMPILE_ONLY TRUE)  # Only search RTL when cross-compiling

# FPC cross-compiler configuration
set(FPC_EXECUTABLE_NAME "ppcrossa64")
# Expand environment variables for search paths
if(DEFINED ENV{HOME})
    set(FPC_SEARCH_PATHS
        /usr/local/bin
        /opt/homebrew/bin
        "$ENV{HOME}/Applications/fpcupdeluxe/fpc/bin/aarch64-darwin"
        "$ENV{HOME}/Applications/fpcupdeluxe/fpc/bin/x86_64-darwin"
        "$ENV{HOME}/fpcupdeluxe/fpc/bin/aarch64-darwin"
        "$ENV{HOME}/fpcupdeluxe/fpc/bin/x86_64-darwin"
    )
else()
    set(FPC_SEARCH_PATHS
        /usr/local/bin
        /opt/homebrew/bin
    )
endif()

