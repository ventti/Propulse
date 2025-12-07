# macOS host platform detection
if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Darwin")
    if(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "arm64|aarch64|ARM64")
        set(HOST_PLATFORM "macos-arm64")
        set(HOST_OS_FPC "darwin")
        set(HOST_CPU_FPC "aarch64")
    else()
        set(HOST_PLATFORM "macos-x86")
        set(HOST_OS_FPC "darwin")
        set(HOST_CPU_FPC "i386")
    endif()
endif()

# Function: Setup macOS dylib path fixing post-build step
# Parameters:
#   TARGET_NAME - name of the CMake target
#   BINARY_DIR - build directory (CMAKE_BINARY_DIR)
#   REL_OUTPUT_BINARY - relative path to output binary from BINARY_DIR
#   POST_BUILD_SCRIPT - value from toolchain (should be "fix-dylib-paths" to enable)
function(macos_fix_dylib_paths TARGET_NAME BINARY_DIR REL_OUTPUT_BINARY POST_BUILD_SCRIPT)
    if(NOT POST_BUILD_SCRIPT STREQUAL "fix-dylib-paths")
        return()
    endif()
    
    # Create a script file to avoid shell parsing issues - use relative path in script
    file(WRITE ${BINARY_DIR}/fix-dylib-paths.sh "#!/bin/bash\nBINARY=\"${REL_OUTPUT_BINARY}\"\nfor DYLIB in libSDL2 libbass libsoxr; do\n  current=\$(otool -L \"\$BINARY\" 2>/dev/null | grep -i \"\$DYLIB\" | head -1 | awk '{print \$1}' | tr -d ' ')\n  expected=\"@executable_path/\$DYLIB.dylib\"\n  if [ -n \"\$current\" ] && [ \"\$current\" != \"\$expected\" ]; then\n    echo \"  Changing \$DYLIB path: \$current -> \$expected\"\n    install_name_tool -change \"\$current\" \"\$expected\" \"\$BINARY\"\n  fi\ndone\n")
    file(CHMOD ${BINARY_DIR}/fix-dylib-paths.sh FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE)
    add_custom_command(TARGET ${TARGET_NAME} POST_BUILD
        WORKING_DIRECTORY ${BINARY_DIR}
        COMMAND ${CMAKE_COMMAND} -E echo "Fixing dylib paths..."
        COMMAND bash ./fix-dylib-paths.sh || ${CMAKE_COMMAND} -E echo "Note: dylib path fixing skipped - may need manual fix"
        COMMENT "Fixing dylib paths for macOS"
    )
endfunction()

# Function: Setup macOS dSYM generation post-build step (debug builds only)
# Parameters:
#   TARGET_NAME - name of the CMake target
#   BINARY_DIR - build directory (CMAKE_BINARY_DIR)
#   REL_OUTPUT_BINARY - relative path to output binary from BINARY_DIR
#   BUILD_MODE - build mode ("debug" or "release")
function(macos_generate_dsym TARGET_NAME BINARY_DIR REL_OUTPUT_BINARY BUILD_MODE)
    if(NOT BUILD_MODE STREQUAL "debug")
        return()
    endif()
    
    # Create a script to avoid shell parsing issues with pipes
    file(WRITE ${BINARY_DIR}/generate-dsym.sh "#!/bin/bash\ndsymutil ${REL_OUTPUT_BINARY} 2>&1 | grep -v 'warning:.*no debug symbols' || true\n")
    file(CHMOD ${BINARY_DIR}/generate-dsym.sh FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE)
    add_custom_command(TARGET ${TARGET_NAME} POST_BUILD
        WORKING_DIRECTORY ${BINARY_DIR}
        COMMAND ${CMAKE_COMMAND} -E echo "Generating dSYM for macOS symbolication..."
        COMMAND bash ./generate-dsym.sh
        COMMENT "Generating dSYM"
    )
endfunction()

