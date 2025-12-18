cmake_minimum_required(VERSION 3.24)
set(PROJECT_NAME "Propulse")
set(PROJECT_VERSION "0.0.0")
project(${PROJECT_NAME} VERSION ${PROJECT_VERSION} LANGUAGES NONE)

# Project configuration
# Use file(TO_CMAKE_PATH) to ensure paths are properly formatted
file(TO_CMAKE_PATH "${CMAKE_SOURCE_DIR}/src" SRC_DIR)
# Build artifacts go to build directory (CMAKE_BINARY_DIR), not bin/
file(TO_CMAKE_PATH "${CMAKE_SOURCE_DIR}/lib" LIB_DIR)

# Main source files
set(MAIN_SOURCE "${SRC_DIR}/propulse.pas")
set(RESOURCE_FILE "${SRC_DIR}/propulse.res")

# Find all Pascal source files for dependency tracking
file(GLOB_RECURSE ALL_PAS_FILES "${SRC_DIR}/*.pas")

# Include FPC configuration (includes platform detection)
include(cmake/fpc.cmake)

# Unit search paths (relative to src directory)
set(UNIT_PATHS
    -Fu${SRC_DIR}/protracker
    -Fu${SRC_DIR}/cwe
    -Fu${SRC_DIR}/cwe/widgets
    -Fu${SRC_DIR}/screen
    -Fu${SRC_DIR}/dialog
    -Fu${SRC_DIR}/include
    -Fu${SRC_DIR}/include/sdl2
    -Fu${SRC_DIR}/include/bass
    -Fu${SRC_DIR}/include/generics.collections/src
)

# Target platform must be set by toolchain file
# Toolchain files set platform-specific variables (TARGET_PLATFORM, TARGET_CPU, etc.)
if(NOT DEFINED TARGET_PLATFORM)
    message(FATAL_ERROR "TARGET_PLATFORM not set. A toolchain file must be used. Use a CMake preset (e.g., cmake --preset macos-arm64-release).")
endif()

# Construct full paths from subdirectories set by toolchain files
if(DEFINED UNIT_OUTPUT_SUBDIR)
    set(UNIT_OUTPUT_DIR "${SRC_DIR}/lib/${UNIT_OUTPUT_SUBDIR}")
else()
    message(FATAL_ERROR "UNIT_OUTPUT_SUBDIR not set by toolchain file")
endif()

if(DEFINED LIB_DIR_SUBDIR)
    set(LIB_DIR_PLATFORM "${LIB_DIR}/${LIB_DIR_SUBDIR}")
    # Construct LIB_PATHS: platform-specific directory first, then any additional paths from toolchain
    set(LIB_PATHS "-k-L${LIB_DIR_PLATFORM}")
    # Add any additional library paths from toolchain file (e.g., /opt/homebrew/lib for macOS ARM64)
    if(DEFINED LIB_PATHS_EXTRA AND NOT LIB_PATHS_EXTRA STREQUAL "")
        list(APPEND LIB_PATHS ${LIB_PATHS_EXTRA})
    endif()
else()
    message(FATAL_ERROR "LIB_DIR_SUBDIR not set by toolchain file")
endif()

# Build mode (default to release)
if(NOT DEFINED MODE)
    set(MODE "release")
endif()

# Get git describe information at build time
# This will be regenerated on each build via a custom command
set(GIT_DESCRIBE_INC "${SRC_DIR}/include/gitdescribe.inc")
set(GIT_DESCRIBE "unknown")
find_program(GIT_EXECUTABLE git)
if(GIT_EXECUTABLE)
    execute_process(
        COMMAND ${GIT_EXECUTABLE} describe --always --tags --dirty
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        OUTPUT_VARIABLE GIT_DESCRIBE
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
endif()
if(NOT GIT_DESCRIBE OR GIT_DESCRIBE STREQUAL "")
    set(GIT_DESCRIBE "unknown")
endif()
# Write initial version (will be regenerated at build time)
file(WRITE ${GIT_DESCRIBE_INC} "'${GIT_DESCRIBE}'")

# FPC compiler finding and cross-compiler detection is handled in cmake/fpc.cmake

# Compiler flags base
# Get generic FPC base flags (mode, syntax, target flags)
fpc_build_base_flags(FPC_FLAGS_BASE_GENERIC ${TARGET_OS} ${TARGET_CPU})

# Add project-specific paths and output directories
set(FPC_FLAGS_BASE
    ${FPC_FLAGS_BASE_GENERIC}
    -Fi${SRC_DIR}
    -Fl${SRC_DIR}/include/sdl2
    -Fl${SRC_DIR}/include/bass
    -FE${CMAKE_BINARY_DIR}
    -FU${UNIT_OUTPUT_DIR}
)

# Common flags shared between release and debug modes
set(FPC_FLAGS_COMMON
    ${FPC_FLAGS_BASE}
    -gl
    -dBASS_DYNAMIC
    -dDISABLE_SDL2_2_0_5
    -dDISABLE_SDL2_2_0_4
    ${PLATFORM_DEFINES}
)

# Release mode flags
fpc_build_release_flags(FPC_FLAGS_RELEASE_GENERIC)
set(FPC_FLAGS_RELEASE
    ${FPC_FLAGS_COMMON}
    ${FPC_FLAGS_RELEASE_GENERIC}
)

# Debug mode flags
# DEBUG_FORMAT is set by toolchain files
if(NOT DEFINED DEBUG_FORMAT)
    message(FATAL_ERROR "DEBUG_FORMAT not set by toolchain file")
endif()

fpc_build_debug_flags(FPC_FLAGS_DEBUG_GENERIC ${DEBUG_FORMAT})
set(FPC_FLAGS_DEBUG
    ${FPC_FLAGS_COMMON}
    ${FPC_FLAGS_DEBUG_GENERIC}
)

# Select flags based on mode
# Output binaries to build directory
if(MODE STREQUAL "debug")
    set(FPC_FLAGS ${FPC_FLAGS_DEBUG})
    set(OUTPUT_BINARY "${CMAKE_BINARY_DIR}/${PROJECT_NAME}-${TARGET_PLATFORM}-debug${BINARY_EXT}")
else()
    set(FPC_FLAGS ${FPC_FLAGS_RELEASE})
    set(OUTPUT_BINARY "${CMAKE_BINARY_DIR}/${PROJECT_NAME}-${TARGET_PLATFORM}${BINARY_EXT}")
endif()

# Add RTL unit paths (including FCL units like fcl-json)
# RTL configuration is set by toolchain files
fpc_find_rtl_units(UNIT_PATHS ${TARGET_CPU} ${TARGET_OS})

# Create output directories
file(MAKE_DIRECTORY ${UNIT_OUTPUT_DIR})
file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR})

# Custom command to regenerate gitdescribe.inc at build time
# This ensures git describe is always up-to-date
if(GIT_EXECUTABLE)
    # Create a script to run git describe and write to file
    set(GIT_DESCRIBE_SCRIPT "${CMAKE_BINARY_DIR}/generate_git_describe.sh")
    if(CMAKE_HOST_WIN32)
        set(GIT_DESCRIBE_SCRIPT "${CMAKE_BINARY_DIR}/generate_git_describe.bat")
        file(WRITE ${GIT_DESCRIBE_SCRIPT} "@echo off
cd /d \"${CMAKE_SOURCE_DIR}\"
for /f \"delims=\" %%i in ('\"${GIT_EXECUTABLE}\" describe --always --tags --dirty 2^>nul') do set GIT_DESC=%%i
if \"%GIT_DESC%\"==\"\" set GIT_DESC=unknown
echo '%GIT_DESC%' > \"${GIT_DESCRIBE_INC}\"
")
    else()
        file(WRITE ${GIT_DESCRIBE_SCRIPT} "#!/bin/sh
cd \"${CMAKE_SOURCE_DIR}\"
GIT_DESC=\"$(${GIT_EXECUTABLE} describe --always --tags --dirty 2>/dev/null)\"
if [ -z \"$GIT_DESC\" ]; then
    GIT_DESC=\"unknown\"
fi
echo \"'$GIT_DESC'\" > \"${GIT_DESCRIBE_INC}\"
")
        file(CHMOD ${GIT_DESCRIBE_SCRIPT} FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE)
    endif()
    
    add_custom_command(
        OUTPUT ${GIT_DESCRIBE_INC}
        COMMAND ${GIT_DESCRIBE_SCRIPT}
        COMMENT "Generating git describe information"
        VERBATIM
    )
else()
    # No git available, create file with "unknown"
    file(WRITE ${GIT_DESCRIBE_INC} "'unknown'")
endif()

# Convert absolute paths to relative paths from build directory to avoid FPC linker script issues with parentheses
# This helps FPC generate linker scripts with relative paths that don't have shell parsing issues
file(RELATIVE_PATH REL_SRC_DIR ${CMAKE_BINARY_DIR} ${SRC_DIR})
file(RELATIVE_PATH REL_UNIT_OUTPUT_DIR ${CMAKE_BINARY_DIR} ${UNIT_OUTPUT_DIR})
file(RELATIVE_PATH REL_LIB_DIR_PLATFORM ${CMAKE_BINARY_DIR} ${LIB_DIR_PLATFORM})
file(RELATIVE_PATH REL_MAIN_SOURCE ${CMAKE_BINARY_DIR} ${MAIN_SOURCE})
file(RELATIVE_PATH REL_OUTPUT_BINARY ${CMAKE_BINARY_DIR} ${OUTPUT_BINARY})

# Build relative unit paths
set(REL_UNIT_PATHS
    "-Fu${REL_SRC_DIR}/protracker"
    "-Fu${REL_SRC_DIR}/cwe"
    "-Fu${REL_SRC_DIR}/cwe/widgets"
    "-Fu${REL_SRC_DIR}/screen"
    "-Fu${REL_SRC_DIR}/dialog"
    "-Fu${REL_SRC_DIR}/include"
    "-Fu${REL_SRC_DIR}/include/sdl2"
    "-Fu${REL_SRC_DIR}/include/bass"
    "-Fu${REL_SRC_DIR}/include/generics.collections/src"
)

# Add RTL paths to REL_UNIT_PATHS (keep as absolute paths since they're outside project)
# Use unified RTL_UNIT_PATH set by the RTL finding code above
fpc_add_rtl_paths(REL_UNIT_PATHS ${RTL_UNIT_PATH})

# Build relative FPC flags
# Get generic FPC base flags (reuse the same function)
fpc_build_base_flags(REL_FPC_FLAGS_BASE_GENERIC ${TARGET_OS} ${TARGET_CPU})

# Add project-specific paths and output directories (relative paths)
set(REL_FPC_FLAGS_BASE
    ${REL_FPC_FLAGS_BASE_GENERIC}
    "-Fi${REL_SRC_DIR}"
    "-Fl${REL_SRC_DIR}/include/sdl2"
    "-Fl${REL_SRC_DIR}/include/bass"
    "-FE."
    "-FU${REL_UNIT_OUTPUT_DIR}"
)

# Common flags with relative paths
set(REL_FPC_FLAGS_COMMON
    ${REL_FPC_FLAGS_BASE}
    -gl
    -dBASS_DYNAMIC
    -dDISABLE_SDL2_2_0_5
    -dDISABLE_SDL2_2_0_4
    ${PLATFORM_DEFINES}
)

# Select relative flags based on mode
if(MODE STREQUAL "debug")
    # Use DEBUG_FORMAT from toolchain file (already set above)
    fpc_build_debug_flags(REL_FPC_FLAGS_DEBUG_GENERIC ${DEBUG_FORMAT})
    set(REL_FPC_FLAGS
        ${REL_FPC_FLAGS_COMMON}
        ${REL_FPC_FLAGS_DEBUG_GENERIC}
    )
else()
    fpc_build_release_flags(REL_FPC_FLAGS_RELEASE_GENERIC)
    set(REL_FPC_FLAGS
        ${REL_FPC_FLAGS_COMMON}
        ${REL_FPC_FLAGS_RELEASE_GENERIC}
    )
endif()

# Build relative library paths
# Start with the platform-specific library directory (relative)
set(REL_LIB_PATHS "-k-L${REL_LIB_DIR_PLATFORM}")
# Add any additional library paths from toolchain file (keep absolute paths as-is)
if(DEFINED LIB_PATHS_EXTRA AND NOT LIB_PATHS_EXTRA STREQUAL "")
    # LIB_PATHS_EXTRA may contain additional paths like -k-L/opt/homebrew/lib
    # Append them to REL_LIB_PATHS (they're already absolute, so no conversion needed)
    list(APPEND REL_LIB_PATHS ${LIB_PATHS_EXTRA})
endif()

# macOS-specific linker configuration
# Note: FPC automatically adds -no_dead_strip_inits_and_terms internally for macOS,
# which causes a linker warning about the obsolete flag. Modern linkers preserve
# initialization/termination code automatically, so this flag is redundant.
# The warning is harmless and the linker works correctly. This is an FPC limitation
# that would require modifying FPC's source code to fix properly.

# Custom command to build the binary using FPC
# Use relative paths and set working directory to build directory to avoid FPC linker script issues
# Use VERBATIM to ensure proper quoting of arguments with spaces
add_custom_command(
    OUTPUT ${OUTPUT_BINARY}
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    COMMAND ${CMAKE_COMMAND} -E echo "Building ${PROJECT_NAME} for ${TARGET_PLATFORM} mode ${MODE}"
    COMMAND ${CMAKE_COMMAND} -E echo "  Target: ${CMAKE_SYSTEM_NAME} ${CMAKE_SYSTEM_PROCESSOR} (${TARGET_CPU}-${TARGET_OS})"
    COMMAND ${FPC_EXECUTABLE}
        ${REL_FPC_FLAGS}
        ${REL_UNIT_PATHS}
        "${REL_MAIN_SOURCE}"
        "-o${REL_OUTPUT_BINARY}"
        -k-lSDL2
        -k-lbass
        -k-lsoxr
        ${REL_LIB_PATHS}
    DEPENDS ${MAIN_SOURCE} ${RESOURCE_FILE} ${ALL_PAS_FILES} ${GIT_DESCRIBE_INC}
    COMMENT "Compiling ${PROJECT_NAME} for ${TARGET_PLATFORM}"
    VERBATIM
)

# Custom target that depends on the binary output
# Use relative paths for post-build commands to avoid shell parsing issues
add_custom_target(${PROJECT_NAME} ALL
    DEPENDS ${OUTPUT_BINARY}
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    COMMAND ${CMAKE_COMMAND} -E echo "Build complete: Propulse binary created"
    COMMAND ${CMAKE_COMMAND} -E copy_directory_if_different "${REL_LIB_DIR_PLATFORM}" "."
)

# macOS-specific post-build steps
if(TARGET_OS STREQUAL "darwin")
    macos_fix_dylib_paths(${PROJECT_NAME} ${CMAKE_BINARY_DIR} ${REL_OUTPUT_BINARY} ${POST_BUILD_SCRIPT})
    macos_generate_dsym(${PROJECT_NAME} ${CMAKE_BINARY_DIR} ${REL_OUTPUT_BINARY} ${MODE})
endif()

# Determine binary name based on target and mode
if(MODE STREQUAL "debug")
    set(PACKAGE_BINARY_NAME "${PROJECT_NAME}-${TARGET_PLATFORM}-debug${BINARY_EXT}")
else()
    set(PACKAGE_BINARY_NAME "${PROJECT_NAME}-${TARGET_PLATFORM}${BINARY_EXT}")
endif()

# Platform-specific library lists
# Default binary rename (used for macOS and Linux)
set(BINARY_RENAME "${PROJECT_NAME}")

if(TARGET_OS STREQUAL "win64")
    set(PLATFORM_LIBS
        "${CMAKE_BINARY_DIR}/bass.dll"
        "${CMAKE_BINARY_DIR}/SDL2.dll"
        "${CMAKE_BINARY_DIR}/libsoxr.dll"
    )
    set(BINARY_RENAME "${PROJECT_NAME}.exe")
    set(BINARY_PERMISSIONS "")
elseif(TARGET_OS STREQUAL "darwin")
    set(PLATFORM_LIBS
        "${CMAKE_BINARY_DIR}/libbass.dylib"
        "${CMAKE_BINARY_DIR}/libSDL2.dylib"
        "${CMAKE_BINARY_DIR}/libsoxr.dylib"
    )
    set(BINARY_PERMISSIONS PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
elseif(TARGET_OS STREQUAL "linux")
    set(PLATFORM_LIBS
        "${CMAKE_BINARY_DIR}/libbass.so"
        "${CMAKE_BINARY_DIR}/libSDL2-2.0.so.0"
        "${CMAKE_BINARY_DIR}/libsoxr.so.0"
    )
    set(BINARY_PERMISSIONS PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)
endif()

# Common install rules for binaries and libraries
# Install binary from build directory
install(FILES "${CMAKE_BINARY_DIR}/${PACKAGE_BINARY_NAME}"
    DESTINATION "."
    RENAME "${BINARY_RENAME}"
    ${BINARY_PERMISSIONS}
    COMPONENT Runtime
)

# Install platform-specific libraries
install(FILES ${PLATFORM_LIBS}
    DESTINATION "."
    COMPONENT Runtime
    OPTIONAL
)

# Install data directory
install(DIRECTORY "${CMAKE_SOURCE_DIR}/data"
    DESTINATION "."
    COMPONENT Runtime
)

# Install docs directory
install(DIRECTORY "${CMAKE_SOURCE_DIR}/docs"
    DESTINATION "."
    COMPONENT Runtime
)

# Install license
install(FILES "${CMAKE_SOURCE_DIR}/license.txt"
    DESTINATION "."
    COMPONENT Runtime
    OPTIONAL
)

# macOS-specific post-install: Fix dylib paths
if(TARGET_OS STREQUAL "darwin")
    # Create a script file to avoid escaping issues and ensure proper error handling
    # Use relative path from build directory to avoid issues with parentheses in paths
    file(RELATIVE_PATH REL_FIX_SCRIPT ${CMAKE_BINARY_DIR} ${CMAKE_BINARY_DIR}/fix-dylib-install.sh)
    set(FIX_DYLIB_SCRIPT "${CMAKE_BINARY_DIR}/fix-dylib-install.sh")
    file(WRITE ${FIX_DYLIB_SCRIPT} "#!/bin/bash
INSTALL_PREFIX=\"\$1\"
BINARY=\"\${INSTALL_PREFIX}/Propulse\"
if [ ! -f \"\${BINARY}\" ]; then
    echo \"Warning: Binary not found at \${BINARY}, skipping dylib path fix\"
    exit 0
fi
for DYLIB in libSDL2 libbass libsoxr; do
    current=\$(otool -L \"\${BINARY}\" 2>/dev/null | grep -i \"\${DYLIB}\" | head -1 | awk '{print \$1}' | tr -d ' ')
    expected=\"@executable_path/\${DYLIB}.dylib\"
    if [ -n \"\${current}\" ] && [ \"\${current}\" != \"\${expected}\" ]; then
        echo \"  Changing \${DYLIB} path: \${current} -> \${expected}\"
        install_name_tool -change \"\${current}\" \"\${expected}\" \"\${BINARY}\" 2>&1 || echo \"  Warning: Failed to change \${DYLIB} path\"
    fi
done
exit 0
")
    file(CHMOD ${FIX_DYLIB_SCRIPT} FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE)
    install(CODE "
        set(SCRIPT_PATH \"${FIX_DYLIB_SCRIPT}\")
        set(INSTALL_DIR \"\${CMAKE_INSTALL_PREFIX}\")
        if(DEFINED ENV{DESTDIR})
            set(INSTALL_DIR \"\$ENV{DESTDIR}\${CMAKE_INSTALL_PREFIX}\")
        endif()
        execute_process(
            COMMAND bash \"${FIX_DYLIB_SCRIPT}\" \"\${INSTALL_DIR}\"
            RESULT_VARIABLE FIX_RESULT
            OUTPUT_VARIABLE FIX_OUTPUT
            ERROR_VARIABLE FIX_ERROR
            ERROR_QUIET
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )
        if(FIX_RESULT AND NOT FIX_RESULT EQUAL 0)
            message(WARNING \"dylib path fixing returned error: \${FIX_RESULT}\")
            if(FIX_OUTPUT)
                message(WARNING \"Output: \${FIX_OUTPUT}\")
            endif()
            if(FIX_ERROR)
                message(WARNING \"Error: \${FIX_ERROR}\")
            endif()
        endif()
    " COMPONENT Runtime)
endif()

# CPack configuration for packaging
set(CPACK_PACKAGE_NAME "${PROJECT_NAME}")
set(CPACK_PACKAGE_VERSION "${PROJECT_VERSION}")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Propulse Tracker - A ProTracker clone")
set(CPACK_GENERATOR "ZIP")
set(CPACK_PACKAGE_DIRECTORY "${CMAKE_SOURCE_DIR}/release")
set(CPACK_PACKAGE_FILE_NAME "${PROJECT_NAME}-${TARGET_PLATFORM}")

# Configure CPack components
set(CPACK_COMPONENT_RUNTIME_DISPLAY_NAME "Propulse Tracker")
set(CPACK_COMPONENT_RUNTIME_DESCRIPTION "Propulse Tracker runtime files")
set(CPACK_COMPONENTS_ALL Runtime)

# Include CPack (must be last)
include(CPack)

# Note: To clean build artifacts, simply remove the build/ directory:
#   rm -rf build/
# To clean packages, remove the release/ directory:
#   rm -rf release/
# CMake's standard 'clean' target (cmake --build --target clean) will clean
# build artifacts within the build directory.

