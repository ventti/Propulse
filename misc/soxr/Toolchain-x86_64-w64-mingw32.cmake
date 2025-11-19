# CMake toolchain file for cross-compiling to Windows x64 using MinGW-w64
# Based on the example from soxr/INSTALL

SET(CMAKE_SYSTEM_NAME Windows)
SET(CMAKE_SYSTEM_PROCESSOR x86_64)

# Find MinGW-w64 compilers
SET(CMAKE_C_COMPILER x86_64-w64-mingw32-gcc)
SET(CMAKE_CXX_COMPILER x86_64-w64-mingw32-g++)

# Optional: Set resource compiler and other tools if available
find_program(CMAKE_RC_COMPILER NAMES x86_64-w64-mingw32-windres)
find_program(CMAKE_AR NAMES x86_64-w64-mingw32-ar)
find_program(CMAKE_RANLIB NAMES x86_64-w64-mingw32-ranlib)

# Set find root path (where MinGW-w64 is installed)
# On macOS with Homebrew, this is typically /usr/local or /opt/homebrew
if(EXISTS "/opt/homebrew/opt/mingw-w64")
    SET(CMAKE_FIND_ROOT_PATH /opt/homebrew/opt/mingw-w64)
elseif(EXISTS "/usr/local/opt/mingw-w64")
    SET(CMAKE_FIND_ROOT_PATH /usr/local/opt/mingw-w64)
else()
    # Try to find it via which
    execute_process(
        COMMAND which x86_64-w64-mingw32-gcc
        OUTPUT_VARIABLE MINGW_GCC_PATH
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )
    if(MINGW_GCC_PATH)
        get_filename_component(MINGW_BIN_DIR ${MINGW_GCC_PATH} DIRECTORY)
        get_filename_component(MINGW_ROOT ${MINGW_BIN_DIR} DIRECTORY)
        SET(CMAKE_FIND_ROOT_PATH ${MINGW_ROOT})
    endif()
endif()

# Search for programs in the host environment
SET(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)

# Search for libraries and headers in the target environment
SET(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
SET(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)

