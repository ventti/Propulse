# CMake toolchain file for Windows x64 cross-compilation
# Usage: cmake --preset windows-x64-release -DCMAKE_TOOLCHAIN_FILE=cmake/toolchains/windows-x64.cmake

set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR AMD64)

# Platform-specific configuration
set(TARGET_PLATFORM "windows-x64")
set(TARGET_CPU "x86_64")
set(TARGET_OS "win64")
set(BINARY_EXT ".exe")
set(UNIT_OUTPUT_SUBDIR "x86_64-win64")
set(PLATFORM_DEFINES "-dCPUX86_64;-dTARGET_X64;-dWINDOWS")
set(LIB_DIR_SUBDIR "windows-x64")
set(LIB_PATHS_EXTRA "")
set(POST_BUILD_SCRIPT "")
set(DEBUG_FORMAT "-gs")  # Stabs for Windows

# RTL unit configuration for cross-compilation
set(RTL_SUFFIX "x86_64-win64")
set(RTL_UNIT_SUBDIRS "rtl;rtl-generics;rtl-objpas;rtl-win")
set(FCL_UNIT_SUBDIRS "fcl-base;fcl-extra;fcl-process;fcl-net;fcl-json")
set(RTL_PLATFORM_UNIT_SUBDIRS "winunits-base;winunits-extra")
set(RTL_PATH_SUFFIXES "units/${RTL_SUFFIX};lib/fpc/*/units/${RTL_SUFFIX}")
set(RTL_USE_LINUX_PATHS FALSE)
set(RTL_WARNING_PLATFORM "Windows")

# FPC cross-compiler configuration
set(FPC_EXECUTABLE_NAME "ppcrossx64")
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

