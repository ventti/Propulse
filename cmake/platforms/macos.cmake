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

