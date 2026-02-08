package = "check-for-updates"
version = "dev-1"
source = {
   url = "git+ssh://git@github-ventti/ventti/Propulse.git"
}
description = {
   homepage = "*** please enter a project homepage ***",
   license = "*** please specify a license ***"
}
dependencies = {
   "lua >= 5.3",
   "luastatic >= 0.0.12",
   "Lua-cURL >= 0.3.13"
}
build = {
   type = "builtin",
   modules = {
      ["check-for-updates"] = "check-for-updates.lua"
   }
}
