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

# Include FPC configuration
include(cmake/fpc.cmake)

# Include platform detection
include(cmake/platforms/macos.cmake)
include(cmake/platforms/linux.cmake)
include(cmake/platforms/windows.cmake)

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

# FPC compiler finding and cross-compiler detection is handled in cmake/fpc.cmake

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
)

# Add target flags
# Note: Even cross-compilers like ppcrossx64 need -T flag to specify target OS
# The -P flag is implicit in cross-compiler name, but -T is still needed
if(USE_CROSS_COMPILER)
    # Cross-compiler still needs -T flag for target OS
    list(APPEND FPC_FLAGS_BASE -T${TARGET_OS})
elseif(NOT USE_CROSS_COMPILER)
    # Regular fpc needs both -T and -P
    list(APPEND FPC_FLAGS_BASE
        -T${TARGET_OS}
        -P${TARGET_CPU}
    )
endif()

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
# DEBUG_FORMAT is set by toolchain files
if(NOT DEFINED DEBUG_FORMAT)
    message(FATAL_ERROR "DEBUG_FORMAT not set by toolchain file")
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
    set(OUTPUT_BINARY "${CMAKE_BINARY_DIR}/${PROJECT_NAME}-${TARGET_PLATFORM}-debug${BINARY_EXT}")
else()
    set(FPC_FLAGS ${FPC_FLAGS_RELEASE})
    set(OUTPUT_BINARY "${CMAKE_BINARY_DIR}/${PROJECT_NAME}-${TARGET_PLATFORM}${BINARY_EXT}")
endif()

# Add FCL JSON unit path for macOS builds
if(TARGET_OS STREQUAL "darwin")
    find_path(FCL_JSON_PATH
        NAMES fcl-json
        PATHS ${FPC_SEARCH_BASE_PATHS}
        PATH_SUFFIXES
            units/${TARGET_CPU}-${TARGET_OS}/fcl-json
    )
    if(FCL_JSON_PATH)
        list(APPEND UNIT_PATHS "-Fu${FCL_JSON_PATH}")
    endif()
endif()

# Add RTL unit paths for cross-compilation
# RTL configuration is set by toolchain files
if(DEFINED RTL_SUFFIX)
    # Check if we should search for RTL (only for cross-compilation, or always for Windows/Linux)
    set(SHOULD_SEARCH_RTL TRUE)
    if(DEFINED RTL_CROSSCOMPILE_ONLY AND RTL_CROSSCOMPILE_ONLY AND NOT CMAKE_CROSSCOMPILING)
        set(SHOULD_SEARCH_RTL FALSE)
    endif()
    
    if(SHOULD_SEARCH_RTL)
        # Determine which search paths to use
        if(RTL_USE_LINUX_PATHS)
            set(RTL_SEARCH_PATHS ${FPC_SEARCH_BASE_PATHS_LINUX})
        else()
            set(RTL_SEARCH_PATHS ${FPC_SEARCH_BASE_PATHS})
        endif()
        
        # Find RTL unit directory
        find_path(RTL_UNIT_PATH
            NAMES rtl system.ppu
            PATHS ${RTL_SEARCH_PATHS}
            PATH_SUFFIXES ${RTL_PATH_SUFFIXES}
            NO_DEFAULT_PATH
        )
        
        if(RTL_UNIT_PATH)
            # Add RTL unit paths
            foreach(RTL_SUBDIR ${RTL_UNIT_SUBDIRS})
                list(APPEND UNIT_PATHS "-Fu${RTL_UNIT_PATH}/${RTL_SUBDIR}")
            endforeach()
            # Add base RTL path
            list(APPEND UNIT_PATHS "-Fu${RTL_UNIT_PATH}")
            
            # Add FCL (Free Component Library) unit paths
            foreach(FCL_SUBDIR ${FCL_UNIT_SUBDIRS})
                list(APPEND UNIT_PATHS "-Fu${RTL_UNIT_PATH}/${FCL_SUBDIR}")
            endforeach()
            
            # Add platform-specific unit paths (if any)
            if(DEFINED RTL_PLATFORM_UNIT_SUBDIRS AND NOT RTL_PLATFORM_UNIT_SUBDIRS STREQUAL "")
                foreach(PLATFORM_SUBDIR ${RTL_PLATFORM_UNIT_SUBDIRS})
                    list(APPEND UNIT_PATHS "-Fu${RTL_UNIT_PATH}/${PLATFORM_SUBDIR}")
                endforeach()
            endif()
            
            message(STATUS "Found ${RTL_WARNING_PLATFORM} ${TARGET_CPU} RTL units at: ${RTL_UNIT_PATH}")
        else()
            message(WARNING "${RTL_WARNING_PLATFORM} ${TARGET_CPU} RTL units not found. Cross-compilation may fail.")
            message(WARNING "To cross-compile for ${RTL_WARNING_PLATFORM}, install ${RTL_WARNING_PLATFORM} RTL units using fpcupdeluxe:")
            message(WARNING "  https://github.com/newpascal/fpcupdeluxe/releases")
            message(WARNING "Or build RTL units from FPC source")
        endif()
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

# Add RTL paths to REL_UNIT_PATHS (keep as absolute paths since they're outside project)
# Use unified RTL_UNIT_PATH set by the RTL finding code above
if(DEFINED RTL_UNIT_PATH AND RTL_UNIT_PATH)
    # Add RTL unit paths
    foreach(RTL_SUBDIR ${RTL_UNIT_SUBDIRS})
        list(APPEND REL_UNIT_PATHS "-Fu${RTL_UNIT_PATH}/${RTL_SUBDIR}")
    endforeach()
    # Add base RTL path
    list(APPEND REL_UNIT_PATHS "-Fu${RTL_UNIT_PATH}")
    
    # Add FCL (Free Component Library) unit paths
    foreach(FCL_SUBDIR ${FCL_UNIT_SUBDIRS})
        list(APPEND REL_UNIT_PATHS "-Fu${RTL_UNIT_PATH}/${FCL_SUBDIR}")
    endforeach()
    
    # Add platform-specific unit paths (if any)
    if(DEFINED RTL_PLATFORM_UNIT_SUBDIRS AND NOT RTL_PLATFORM_UNIT_SUBDIRS STREQUAL "")
        foreach(PLATFORM_SUBDIR ${RTL_PLATFORM_UNIT_SUBDIRS})
            list(APPEND REL_UNIT_PATHS "-Fu${RTL_UNIT_PATH}/${PLATFORM_SUBDIR}")
        endforeach()
    endif()
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
)

# Add target flags
# Note: Even cross-compilers like ppcrossx64 need -T flag to specify target OS
if(USE_CROSS_COMPILER)
    # Cross-compiler still needs -T flag for target OS
    list(APPEND REL_FPC_FLAGS_BASE "-T${TARGET_OS}")
elseif(NOT USE_CROSS_COMPILER)
    # Regular fpc needs both -T and -P
    list(APPEND REL_FPC_FLAGS_BASE
        "-T${TARGET_OS}"
        "-P${TARGET_CPU}"
    )
endif()

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
    set(REL_DEBUG_FORMAT ${DEBUG_FORMAT})
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
# Start with the platform-specific library directory (relative)
set(REL_LIB_PATHS "-k-L${REL_LIB_DIR_PLATFORM}")
# Add any additional library paths from toolchain file (keep absolute paths as-is)
if(DEFINED LIB_PATHS_EXTRA AND NOT LIB_PATHS_EXTRA STREQUAL "")
    # LIB_PATHS_EXTRA may contain additional paths like -k-L/opt/homebrew/lib
    # Append them to REL_LIB_PATHS (they're already absolute, so no conversion needed)
    list(APPEND REL_LIB_PATHS ${LIB_PATHS_EXTRA})
endif()

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
    DEPENDS ${MAIN_SOURCE} ${RESOURCE_FILE} ${ALL_PAS_FILES}
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
    set(PACKAGE_BINARY_NAME "${PROJECT_NAME}-${TARGET_PLATFORM}-debug${BINARY_EXT}")
else()
    set(PACKAGE_BINARY_NAME "${PROJECT_NAME}-${TARGET_PLATFORM}${BINARY_EXT}")
endif()

# Install rules for binaries and libraries
if(TARGET_OS STREQUAL "win64")
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
    
elseif(TARGET_OS STREQUAL "darwin")
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
elseif(TARGET_OS STREQUAL "linux")
    # Install binary from build directory
    install(FILES "${CMAKE_BINARY_DIR}/${PACKAGE_BINARY_NAME}"
        DESTINATION "."
        RENAME "Propulse"
        PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE
        COMPONENT Runtime
    )
    
    # Install shared libraries from build directory
    install(FILES
        "${CMAKE_BINARY_DIR}/libbass.so"
        "${CMAKE_BINARY_DIR}/libSDL2-2.0.so.0"
        "${CMAKE_BINARY_DIR}/libsoxr.so.0"
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

