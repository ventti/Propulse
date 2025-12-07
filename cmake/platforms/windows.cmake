# Windows host platform detection
if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Windows")
    set(HOST_PLATFORM "windows-x64")
    set(HOST_OS_FPC "win64")
    set(HOST_CPU_FPC "x86_64")
endif()

