package = "check-for-updates"
source = {
    url = "git+https://github.com/my-username/my-rock"
}
build = {
   type = "builtin",
   modules = {}
}
version = "0.1.0-1"
dependencies = {
    "lua >= 5.1",
    "luastatic >= 0.1.0",
    "Lua-cURL >= 0.3.13"
}