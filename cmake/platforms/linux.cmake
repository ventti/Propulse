# Linux host platform detection
if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Linux")
    if(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "arm64|aarch64|ARM64")
        set(HOST_PLATFORM "linux-arm64")
        set(HOST_OS_FPC "linux")
        set(HOST_CPU_FPC "aarch64")
    else()
        set(HOST_PLATFORM "linux-x64")
        set(HOST_OS_FPC "linux")
        set(HOST_CPU_FPC "x86_64")
    endif()
endif()

