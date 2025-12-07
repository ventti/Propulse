# FPC (FreePascal Compiler) configuration
# Common FPC search paths for find_path calls
# Expand environment variables for user-specific paths
set(FPC_SEARCH_BASE_PATHS
    /usr/local/lib/fpc
    /opt/homebrew/lib/fpc
    "$ENV{HOME}/Applications/fpcupdeluxe/fpc"
    "$ENV{HOME}/fpcupdeluxe/fpc"
)
# Add Linux-specific paths
set(FPC_SEARCH_BASE_PATHS_LINUX ${FPC_SEARCH_BASE_PATHS} /usr/lib/fpc)

# Find FPC compiler
# For cross-compilation, toolchain files set FPC_EXECUTABLE_NAME and FPC_SEARCH_PATHS
# For native builds, use regular fpc compiler
if(CMAKE_CROSSCOMPILING)
    if(DEFINED FPC_EXECUTABLE_NAME)
        # Use cross-compiler specified in toolchain file
        if(DEFINED FPC_SEARCH_PATHS)
            find_program(FPC_EXECUTABLE ${FPC_EXECUTABLE_NAME} PATHS ${FPC_SEARCH_PATHS} NO_DEFAULT_PATH)
        endif()
        # If not found in specified paths, try system PATH
        if(NOT FPC_EXECUTABLE)
            find_program(FPC_EXECUTABLE ${FPC_EXECUTABLE_NAME})
        endif()
    else()
        # Toolchain file didn't set FPC_EXECUTABLE_NAME, fall back to regular fpc
        # (This shouldn't happen if toolchain files are properly configured)
        message(STATUS "Toolchain file didn't set FPC_EXECUTABLE_NAME, using regular fpc")
        find_program(FPC_EXECUTABLE fpc)
    endif()
else()
    # Native build: use regular fpc compiler
    find_program(FPC_EXECUTABLE fpc)
endif()

if(NOT FPC_EXECUTABLE)
    message(FATAL_ERROR "FreePascal Compiler (fpc) not found. Please install FPC 3.2+")
endif()

# Use CMake's built-in cross-compilation detection
# CMAKE_CROSSCOMPILING is automatically set by CMake when CMAKE_SYSTEM_NAME != CMAKE_HOST_SYSTEM_NAME

# Check if we're using a cross-compiler (ppcross*)
get_filename_component(FPC_EXE_NAME ${FPC_EXECUTABLE} NAME)
if(FPC_EXE_NAME MATCHES "^ppcross")
    set(USE_CROSS_COMPILER TRUE)
    message(STATUS "Using cross-compiler: ${FPC_EXECUTABLE}")
else()
    set(USE_CROSS_COMPILER FALSE)
endif()

