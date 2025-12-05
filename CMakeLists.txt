cmake_minimum_required(VERSION 3.24)
project(Propulse VERSION 0.10.0 LANGUAGES NONE)

# Project configuration
set(PROJECT_NAME "Propulse")
# Use file(TO_CMAKE_PATH) to ensure paths are properly formatted
file(TO_CMAKE_PATH "${CMAKE_SOURCE_DIR}/src" SRC_DIR)
# Build artifacts go to build directory (CMAKE_BINARY_DIR), not bin/
file(TO_CMAKE_PATH "${CMAKE_SOURCE_DIR}/lib" LIB_DIR)

# Main source files
set(MAIN_SOURCE "${SRC_DIR}/propulse.pas")
set(RESOURCE_FILE "${SRC_DIR}/propulse.res")

# Find all Pascal source files for dependency tracking
file(GLOB_RECURSE ALL_PAS_FILES "${SRC_DIR}/*.pas")

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

# Detect host platform
if(APPLE)
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "arm64|aarch64")
        set(HOST_PLATFORM "macos-arm64")
        set(HOST_OS_FPC "darwin")
        set(HOST_CPU_FPC "aarch64")
    else()
        set(HOST_PLATFORM "macos-x86")
        set(HOST_OS_FPC "darwin")
        set(HOST_CPU_FPC "i386")
    endif()
elseif(UNIX)
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "arm64|aarch64")
        set(HOST_PLATFORM "linux-arm64")
        set(HOST_OS_FPC "linux")
        set(HOST_CPU_FPC "aarch64")
    else()
        set(HOST_PLATFORM "linux-x64")
        set(HOST_OS_FPC "linux")
        set(HOST_CPU_FPC "x86_64")
    endif()
elseif(WIN32)
    set(HOST_PLATFORM "windows-x64")
    set(HOST_OS_FPC "win64")
    set(HOST_CPU_FPC "x86_64")
endif()

# Build target selection (default to host platform)
if(NOT DEFINED BUILD_TARGET)
    set(BUILD_TARGET "${HOST_PLATFORM}")
endif()

# Parse target into OS and CPU
if(BUILD_TARGET STREQUAL "macos-arm64")
    set(TARGET_CPU "aarch64")
    set(TARGET_OS "darwin")
    set(BINARY_EXT "")
    set(UNIT_OUTPUT_DIR "${SRC_DIR}/lib/aarch64-darwin")
    set(PLATFORM_DEFINES "-dCPUAARCH64;-dTARGET_ARM64;-dUSENATIVECODE;-dENABLE_SOXR;-dENABLE_SOXR_FORCED")
    set(LIB_DIR_PLATFORM "${LIB_DIR}/macos-arm64")
    set(LIB_PATHS "-k-L${LIB_DIR_PLATFORM}" "-k-L/opt/homebrew/lib")
    set(POST_BUILD_SCRIPT "fix-dylib-paths")
elseif(BUILD_TARGET STREQUAL "windows-x64")
    set(TARGET_CPU "x86_64")
    set(TARGET_OS "win64")
    set(BINARY_EXT ".exe")
    set(UNIT_OUTPUT_DIR "${SRC_DIR}/lib/x86_64-win64")
    set(PLATFORM_DEFINES "-dCPUX86_64;-dTARGET_X64;-dWINDOWS")
    set(LIB_DIR_PLATFORM "${LIB_DIR}/windows-x64")
    set(LIB_PATHS "-k-L${LIB_DIR_PLATFORM}")
    set(POST_BUILD_SCRIPT "")
else()
    message(FATAL_ERROR "Unknown target: ${BUILD_TARGET}. Available targets: macos-arm64, windows-x64")
endif()

# Build mode (default to release)
if(NOT DEFINED MODE)
    set(MODE "release")
endif()

# Find FPC compiler
find_program(FPC_EXECUTABLE fpc)
if(NOT FPC_EXECUTABLE)
    message(FATAL_ERROR "FreePascal Compiler (fpc) not found. Please install FPC 3.2+")
endif()

# Check if cross-compiling
set(IS_CROSS_COMPILE FALSE)
if(NOT (TARGET_OS STREQUAL HOST_OS_FPC))
    set(IS_CROSS_COMPILE TRUE)
endif()

# Compiler flags base
set(FPC_FLAGS_BASE
    -Mdelphi
    -Sc
    -Cg
    -Fi${SRC_DIR}
    -Fl${SRC_DIR}/include/sdl2
    -Fl${SRC_DIR}/include/bass
    -FE${CMAKE_BINARY_DIR}
    -FU${UNIT_OUTPUT_DIR}
    -Xd
    -T${TARGET_OS}
    -P${TARGET_CPU}
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
set(FPC_FLAGS_RELEASE
    ${FPC_FLAGS_COMMON}
    -O3
    -XX
    -Xs
    -gv
    -dRELEASE
)

# Debug mode flags
if(TARGET_OS STREQUAL "darwin")
    set(DEBUG_FORMAT "-gw")  # DWARF for macOS
else()
    set(DEBUG_FORMAT "-gs")  # Stabs for other platforms
endif()

set(FPC_FLAGS_DEBUG
    ${FPC_FLAGS_COMMON}
    -g
    -gh
    -Cr
    -Ct
    -Ci
    -Co
    -Sa
    ${DEBUG_FORMAT}
    -dDEBUG
)

# Select flags based on mode
# Output binaries to build directory
if(MODE STREQUAL "debug")
    set(FPC_FLAGS ${FPC_FLAGS_DEBUG})
    set(OUTPUT_BINARY "${CMAKE_BINARY_DIR}/${PROJECT_NAME}-${BUILD_TARGET}-debug${BINARY_EXT}")
else()
    set(FPC_FLAGS ${FPC_FLAGS_RELEASE})
    set(OUTPUT_BINARY "${CMAKE_BINARY_DIR}/${PROJECT_NAME}-${BUILD_TARGET}${BINARY_EXT}")
endif()

# Add FCL JSON unit path for macOS builds
if(TARGET_OS STREQUAL "darwin")
    find_path(FCL_JSON_PATH
        NAMES fcl-json
        PATHS
            /usr/local/lib/fpc
            /opt/homebrew/lib/fpc
        PATH_SUFFIXES
            units/${TARGET_CPU}-${TARGET_OS}/fcl-json
    )
    if(FCL_JSON_PATH)
        list(APPEND UNIT_PATHS "-Fu${FCL_JSON_PATH}")
    endif()
endif()

# Add Windows RTL unit paths for Windows cross-compilation
if(TARGET_OS STREQUAL "win64")
    # Search for Windows RTL units in common FPC installation locations
    set(WIN64_RTL_SEARCH_PATHS
        /usr/local/lib/fpc/*/units/x86_64-win64
        $ENV{HOME}/Applications/fpcupdeluxe/fpc/units/x86_64-win64
        $ENV{HOME}/fpcupdeluxe/fpc/units/x86_64-win64
        $ENV{HOME}/fpcupdeluxe/fpc/lib/fpc/*/units/x86_64-win64
    )
    
    # Try to find Windows RTL unit directory
    find_path(WIN64_RTL_UNIT_PATH
        NAMES rtl system.ppu
        PATHS
            /usr/local/lib/fpc
            $ENV{HOME}/Applications/fpcupdeluxe/fpc
            $ENV{HOME}/fpcupdeluxe/fpc
        PATH_SUFFIXES
            units/x86_64-win64
            lib/fpc/*/units/x86_64-win64
        NO_DEFAULT_PATH
    )
    
    if(WIN64_RTL_UNIT_PATH)
        # Add RTL unit paths
        list(APPEND UNIT_PATHS
            "-Fu${WIN64_RTL_UNIT_PATH}/rtl"
            "-Fu${WIN64_RTL_UNIT_PATH}"
            "-Fu${WIN64_RTL_UNIT_PATH}/rtl-generics"
            "-Fu${WIN64_RTL_UNIT_PATH}/rtl-objpas"
            "-Fu${WIN64_RTL_UNIT_PATH}/rtl-win"
        )
        # Add FCL (Free Component Library) unit paths
        list(APPEND UNIT_PATHS
            "-Fu${WIN64_RTL_UNIT_PATH}/fcl-base"
            "-Fu${WIN64_RTL_UNIT_PATH}/fcl-extra"
            "-Fu${WIN64_RTL_UNIT_PATH}/fcl-process"
            "-Fu${WIN64_RTL_UNIT_PATH}/fcl-net"
            "-Fu${WIN64_RTL_UNIT_PATH}/fcl-json"
        )
        # Add Windows-specific unit paths
        list(APPEND UNIT_PATHS
            "-Fu${WIN64_RTL_UNIT_PATH}/winunits-base"
            "-Fu${WIN64_RTL_UNIT_PATH}/winunits-extra"
        )
        message(STATUS "Found Windows RTL units at: ${WIN64_RTL_UNIT_PATH}")
    else()
        message(WARNING "Windows x64 RTL units not found. Cross-compilation may fail.")
        message(WARNING "To cross-compile for Windows, install Windows RTL units using fpcupdeluxe:")
        message(WARNING "  https://github.com/newpascal/fpcupdeluxe/releases")
        message(WARNING "Or build RTL units from FPC source (see bootstrap-mac.sh for example)")
    endif()
endif()

# Create output directories
file(MAKE_DIRECTORY ${UNIT_OUTPUT_DIR})
file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR})

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

# Add Windows RTL paths to REL_UNIT_PATHS (keep as absolute paths since they're outside project)
if(TARGET_OS STREQUAL "win64" AND WIN64_RTL_UNIT_PATH)
    list(APPEND REL_UNIT_PATHS
        "-Fu${WIN64_RTL_UNIT_PATH}/rtl"
        "-Fu${WIN64_RTL_UNIT_PATH}"
        "-Fu${WIN64_RTL_UNIT_PATH}/rtl-generics"
        "-Fu${WIN64_RTL_UNIT_PATH}/rtl-objpas"
        "-Fu${WIN64_RTL_UNIT_PATH}/rtl-win"
        "-Fu${WIN64_RTL_UNIT_PATH}/fcl-base"
        "-Fu${WIN64_RTL_UNIT_PATH}/fcl-extra"
        "-Fu${WIN64_RTL_UNIT_PATH}/fcl-process"
        "-Fu${WIN64_RTL_UNIT_PATH}/fcl-net"
        "-Fu${WIN64_RTL_UNIT_PATH}/fcl-json"
        "-Fu${WIN64_RTL_UNIT_PATH}/winunits-base"
        "-Fu${WIN64_RTL_UNIT_PATH}/winunits-extra"
    )
endif()

# Build relative FPC flags
set(REL_FPC_FLAGS_BASE
    -Mdelphi
    -Sc
    -Cg
    "-Fi${REL_SRC_DIR}"
    "-Fl${REL_SRC_DIR}/include/sdl2"
    "-Fl${REL_SRC_DIR}/include/bass"
    "-FE."
    "-FU${REL_UNIT_OUTPUT_DIR}"
    -Xd
    "-T${TARGET_OS}"
    "-P${TARGET_CPU}"
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
    if(TARGET_OS STREQUAL "darwin")
        set(REL_DEBUG_FORMAT "-gw")
    else()
        set(REL_DEBUG_FORMAT "-gs")
    endif()
    set(REL_FPC_FLAGS
        ${REL_FPC_FLAGS_COMMON}
        -g
        -gh
        -Cr
        -Ct
        -Ci
        -Co
        -Sa
        ${REL_DEBUG_FORMAT}
        -dDEBUG
    )
else()
    set(REL_FPC_FLAGS
        ${REL_FPC_FLAGS_COMMON}
        -O3
        -XX
        -Xs
        -gv
        -dRELEASE
    )
endif()

# Build relative library paths
if(BUILD_TARGET STREQUAL "macos-arm64")
    set(REL_LIB_PATHS "-k-L${REL_LIB_DIR_PLATFORM}" "-k-L/opt/homebrew/lib")
elseif(BUILD_TARGET STREQUAL "windows-x64")
    set(REL_LIB_PATHS "-k-L${REL_LIB_DIR_PLATFORM}")
endif()

# Custom command to build the binary using FPC
# Use relative paths and set working directory to build directory to avoid FPC linker script issues
# Use VERBATIM to ensure proper quoting of arguments with spaces
add_custom_command(
    OUTPUT ${OUTPUT_BINARY}
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
    COMMAND ${CMAKE_COMMAND} -E echo "Building ${PROJECT_NAME} for ${BUILD_TARGET} mode ${MODE}"
    COMMAND ${CMAKE_COMMAND} -E echo "  Target: ${TARGET_CPU}-${TARGET_OS}"
    COMMAND ${FPC_EXECUTABLE}
        ${REL_FPC_FLAGS}
        ${REL_UNIT_PATHS}
        "${REL_MAIN_SOURCE}"
        "-o${REL_OUTPUT_BINARY}"
        -k-lSDL2
        -k-lbass
        -k-lsoxr
        ${REL_LIB_PATHS}
    DEPENDS ${MAIN_SOURCE} ${RESOURCE_FILE} ${ALL_PAS_FILES}
    COMMENT "Compiling ${PROJECT_NAME} for ${BUILD_TARGET}"
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

# Post-build: Fix dylib paths for macOS
# Use relative path for script to avoid shell parsing issues with parentheses
if(TARGET_OS STREQUAL "darwin" AND POST_BUILD_SCRIPT STREQUAL "fix-dylib-paths")
    # Create a script file to avoid shell parsing issues - use relative path in script
    file(WRITE ${CMAKE_BINARY_DIR}/fix-dylib-paths.sh "#!/bin/bash\nBINARY=\"${REL_OUTPUT_BINARY}\"\nfor DYLIB in libSDL2 libbass libsoxr; do\n  current=\$(otool -L \"\$BINARY\" 2>/dev/null | grep -i \"\$DYLIB\" | head -1 | awk '{print \$1}' | tr -d ' ')\n  expected=\"@executable_path/\$DYLIB.dylib\"\n  if [ -n \"\$current\" ] && [ \"\$current\" != \"\$expected\" ]; then\n    echo \"  Changing \$DYLIB path: \$current -> \$expected\"\n    install_name_tool -change \"\$current\" \"\$expected\" \"\$BINARY\"\n  fi\ndone\n")
    file(CHMOD ${CMAKE_BINARY_DIR}/fix-dylib-paths.sh FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE)
    add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
        WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
        COMMAND ${CMAKE_COMMAND} -E echo "Fixing dylib paths..."
        COMMAND bash ./fix-dylib-paths.sh || ${CMAKE_COMMAND} -E echo "Note: dylib path fixing skipped - may need manual fix"
        COMMENT "Fixing dylib paths for macOS"
    )
endif()

# Debug: Generate dSYM for macOS
if(MODE STREQUAL "debug" AND TARGET_OS STREQUAL "darwin")
    # Create a script to avoid shell parsing issues with pipes
    file(WRITE ${CMAKE_BINARY_DIR}/generate-dsym.sh "#!/bin/bash\ndsymutil ${REL_OUTPUT_BINARY} 2>&1 | grep -v 'warning:.*no debug symbols' || true\n")
    file(CHMOD ${CMAKE_BINARY_DIR}/generate-dsym.sh FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE)
    add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
        WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
        COMMAND ${CMAKE_COMMAND} -E echo "Generating dSYM for macOS symbolication..."
        COMMAND bash ./generate-dsym.sh
        COMMENT "Generating dSYM"
    )
endif()

# Determine binary name based on target and mode
if(MODE STREQUAL "debug")
    set(PACKAGE_BINARY_NAME "${PROJECT_NAME}-${BUILD_TARGET}-debug${BINARY_EXT}")
else()
    set(PACKAGE_BINARY_NAME "${PROJECT_NAME}-${BUILD_TARGET}${BINARY_EXT}")
endif()

# Install rules for binaries and libraries
if(BUILD_TARGET STREQUAL "windows-x64")
    # Install binary from build directory
    install(FILES "${CMAKE_BINARY_DIR}/${PACKAGE_BINARY_NAME}"
        DESTINATION "."
        RENAME "Propulse.exe"
        COMPONENT Runtime
    )
    
    # Install DLLs from build directory
    install(FILES
        "${CMAKE_BINARY_DIR}/bass.dll"
        "${CMAKE_BINARY_DIR}/SDL2.dll"
        "${CMAKE_BINARY_DIR}/libsoxr.dll"
        DESTINATION "."
        COMPONENT Runtime
        OPTIONAL
    )
    
    # Install data directory
    install(DIRECTORY "${CMAKE_SOURCE_DIR}/data"
        DESTINATION "."
        COMPONENT Runtime
    )
    
    # Install license
    install(FILES "${CMAKE_SOURCE_DIR}/license.txt"
        DESTINATION "."
        COMPONENT Runtime
        OPTIONAL
    )
    
elseif(BUILD_TARGET STREQUAL "macos-arm64")
    # Install binary from build directory
    install(FILES "${CMAKE_BINARY_DIR}/${PACKAGE_BINARY_NAME}"
        DESTINATION "."
        RENAME "Propulse"
        PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE
        COMPONENT Runtime
    )
    
    # Install dylibs from build directory
    install(FILES
        "${CMAKE_BINARY_DIR}/libbass.dylib"
        "${CMAKE_BINARY_DIR}/libSDL2.dylib"
        "${CMAKE_BINARY_DIR}/libsoxr.dylib"
        DESTINATION "."
        COMPONENT Runtime
        OPTIONAL
    )
    
    # Install data directory
    install(DIRECTORY "${CMAKE_SOURCE_DIR}/data"
        DESTINATION "."
        COMPONENT Runtime
    )
    
    # Install license
    install(FILES "${CMAKE_SOURCE_DIR}/license.txt"
        DESTINATION "."
        COMPONENT Runtime
        OPTIONAL
    )
    
    # Post-install: Fix dylib paths for macOS
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
set(CPACK_PACKAGE_FILE_NAME "${PROJECT_NAME}-${BUILD_TARGET}")

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

