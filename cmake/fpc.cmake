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

# Generic FPC compiler flags
# These are common flags used by most FPC projects

# Function: Build generic FPC base flags
# Parameters:
#   BASE_FLAGS_OUT - output variable name for base flags
#   TARGET_OS - target operating system (darwin, win64, linux)
#   TARGET_CPU - target CPU (aarch64, x86_64, etc.)
function(fpc_build_base_flags BASE_FLAGS_OUT TARGET_OS TARGET_CPU)
    set(BASE_FLAGS
        -Mdelphi
        -Sc
        -Cg
        -Xd
    )
    
    # Add target flags
    # Note: Even cross-compilers like ppcrossx64 need -T flag to specify target OS
    # The -P flag is implicit in cross-compiler name, but -T is still needed
    if(USE_CROSS_COMPILER)
        # Cross-compiler still needs -T flag for target OS
        list(APPEND BASE_FLAGS "-T${TARGET_OS}")
    else()
        # Regular fpc needs both -T and -P
        list(APPEND BASE_FLAGS
            "-T${TARGET_OS}"
            "-P${TARGET_CPU}"
        )
    endif()
    
    set(${BASE_FLAGS_OUT} ${BASE_FLAGS} PARENT_SCOPE)
endfunction()

# Function: Build generic FPC debug flags
# Parameters:
#   DEBUG_FLAGS_OUT - output variable name for debug flags
#   DEBUG_FORMAT - debug format flag (e.g., -gw for DWARF)
function(fpc_build_debug_flags DEBUG_FLAGS_OUT DEBUG_FORMAT)
    set(DEBUG_FLAGS
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
    set(${DEBUG_FLAGS_OUT} ${DEBUG_FLAGS} PARENT_SCOPE)
endfunction()

# Function: Build generic FPC release flags
function(fpc_build_release_flags RELEASE_FLAGS_OUT)
    set(RELEASE_FLAGS
        -O3
        -XX
        -Xs
        -gv
        -dRELEASE
    )
    set(${RELEASE_FLAGS_OUT} ${RELEASE_FLAGS} PARENT_SCOPE)
endfunction()

# Function: Find RTL units and add them to unit paths
# Parameters:
#   UNIT_PATHS_OUT - output variable name for unit paths (will be appended to)
#   TARGET_CPU - target CPU
#   TARGET_OS - target OS
function(fpc_find_rtl_units UNIT_PATHS_OUT TARGET_CPU TARGET_OS)
    # RTL configuration is set by toolchain files
    if(NOT DEFINED RTL_SUFFIX)
        return()
    endif()
    
    # Check if we should search for RTL (only for cross-compilation, or always for Windows/Linux)
    set(SHOULD_SEARCH_RTL TRUE)
    if(DEFINED RTL_CROSSCOMPILE_ONLY AND RTL_CROSSCOMPILE_ONLY AND NOT CMAKE_CROSSCOMPILING)
        set(SHOULD_SEARCH_RTL FALSE)
    endif()
    
    if(NOT SHOULD_SEARCH_RTL)
        return()
    endif()
    
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
        # Get current unit paths
        set(CURRENT_UNIT_PATHS ${${UNIT_PATHS_OUT}})
        
        # Add RTL unit paths
        foreach(RTL_SUBDIR ${RTL_UNIT_SUBDIRS})
            list(APPEND CURRENT_UNIT_PATHS "-Fu${RTL_UNIT_PATH}/${RTL_SUBDIR}")
        endforeach()
        # Add base RTL path
        list(APPEND CURRENT_UNIT_PATHS "-Fu${RTL_UNIT_PATH}")
        
        # Add FCL (Free Component Library) unit paths
        foreach(FCL_SUBDIR ${FCL_UNIT_SUBDIRS})
            list(APPEND CURRENT_UNIT_PATHS "-Fu${RTL_UNIT_PATH}/${FCL_SUBDIR}")
        endforeach()
        
        # Add platform-specific unit paths (if any)
        if(DEFINED RTL_PLATFORM_UNIT_SUBDIRS AND NOT RTL_PLATFORM_UNIT_SUBDIRS STREQUAL "")
            foreach(PLATFORM_SUBDIR ${RTL_PLATFORM_UNIT_SUBDIRS})
                list(APPEND CURRENT_UNIT_PATHS "-Fu${RTL_UNIT_PATH}/${PLATFORM_SUBDIR}")
            endforeach()
        endif()
        
        set(${UNIT_PATHS_OUT} ${CURRENT_UNIT_PATHS} PARENT_SCOPE)
        set(RTL_UNIT_PATH ${RTL_UNIT_PATH} PARENT_SCOPE)  # Make available to caller
        
        message(STATUS "Found ${RTL_WARNING_PLATFORM} ${TARGET_CPU} RTL units at: ${RTL_UNIT_PATH}")
    else()
        message(WARNING "${RTL_WARNING_PLATFORM} ${TARGET_CPU} RTL units not found. Cross-compilation may fail.")
        message(WARNING "To cross-compile for ${RTL_WARNING_PLATFORM}, install ${RTL_WARNING_PLATFORM} RTL units using fpcupdeluxe:")
        message(WARNING "  https://github.com/newpascal/fpcupdeluxe/releases")
        message(WARNING "Or build RTL units from FPC source")
    endif()
endfunction()

# Function: Add RTL unit paths to an existing unit path list
# Parameters:
#   UNIT_PATHS_OUT - output variable name for unit paths (will be appended to)
#   RTL_UNIT_PATH_IN - RTL unit path (must be set by fpc_find_rtl_units first)
function(fpc_add_rtl_paths UNIT_PATHS_OUT RTL_UNIT_PATH_IN)
    if(NOT DEFINED RTL_UNIT_PATH_IN OR RTL_UNIT_PATH_IN STREQUAL "")
        return()
    endif()
    
    # Get current unit paths
    set(CURRENT_UNIT_PATHS ${${UNIT_PATHS_OUT}})
    
    # Add RTL unit paths
    foreach(RTL_SUBDIR ${RTL_UNIT_SUBDIRS})
        list(APPEND CURRENT_UNIT_PATHS "-Fu${RTL_UNIT_PATH_IN}/${RTL_SUBDIR}")
    endforeach()
    # Add base RTL path
    list(APPEND CURRENT_UNIT_PATHS "-Fu${RTL_UNIT_PATH_IN}")
    
    # Add FCL (Free Component Library) unit paths
    foreach(FCL_SUBDIR ${FCL_UNIT_SUBDIRS})
        list(APPEND CURRENT_UNIT_PATHS "-Fu${RTL_UNIT_PATH_IN}/${FCL_SUBDIR}")
    endforeach()
    
    # Add platform-specific unit paths (if any)
    if(DEFINED RTL_PLATFORM_UNIT_SUBDIRS AND NOT RTL_PLATFORM_UNIT_SUBDIRS STREQUAL "")
        foreach(PLATFORM_SUBDIR ${RTL_PLATFORM_UNIT_SUBDIRS})
            list(APPEND CURRENT_UNIT_PATHS "-Fu${RTL_UNIT_PATH_IN}/${PLATFORM_SUBDIR}")
        endforeach()
    endif()
    
    set(${UNIT_PATHS_OUT} ${CURRENT_UNIT_PATHS} PARENT_SCOPE)
endfunction()

