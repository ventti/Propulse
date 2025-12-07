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

