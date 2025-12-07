# CMake toolchain file for Linux ARM64 cross-compilation
# Usage: cmake --preset linux-arm64-release -DCMAKE_TOOLCHAIN_FILE=cmake/toolchains/linux-arm64.cmake

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

# Platform-specific configuration
set(TARGET_PLATFORM "linux-arm64")
set(TARGET_CPU "aarch64")
set(TARGET_OS "linux")
set(BINARY_EXT "")
set(UNIT_OUTPUT_SUBDIR "aarch64-linux")
set(PLATFORM_DEFINES "-dCPUAARCH64;-dTARGET_ARM64;-dUSENATIVECODE")
set(LIB_DIR_SUBDIR "linux-arm64")
set(LIB_PATHS_EXTRA "")
set(POST_BUILD_SCRIPT "")
set(DEBUG_FORMAT "-gs")  # Stabs for Linux

# RTL unit configuration for cross-compilation
set(RTL_SUFFIX "aarch64-linux")
set(RTL_UNIT_SUBDIRS "rtl;rtl-generics;rtl-objpas;rtl-unix")
set(FCL_UNIT_SUBDIRS "fcl-base;fcl-extra;fcl-process;fcl-net;fcl-json")
set(RTL_PLATFORM_UNIT_SUBDIRS "")
set(RTL_PATH_SUFFIXES "units/${RTL_SUFFIX};lib/fpc/*/units/${RTL_SUFFIX};*/units/${RTL_SUFFIX}")
set(RTL_USE_LINUX_PATHS TRUE)
set(RTL_WARNING_PLATFORM "Linux")

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

