-- check-for-updates.lua
--
-- Replaces tools/scripts/check-for-updates.sh with a pure-Lua implementation
-- intended to be compiled into a small executable via luastatic.
--
-- Notes:
-- - Uses the system's `curl` command (same as the shell script did).
-- - Expects Propulse binary in the current working directory.

local VERSION_URL = "https://www.dropbox.com/scl/fi/qls23vtmsb1bff3jjjhwx/version.txt?rlkey=og28di232duaelbg8ak2xn74t&st=o6h9f6qz&dl=0"

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function capture(cmd)
  local p = io.popen(cmd, "r")
  if not p then
    return nil, "failed to run command: " .. cmd
  end
  local out = p:read("*a") or ""
  local ok, _, code = p:close()
  -- Lua versions differ: `close()` can return true/nil or status string.
  if ok == true then
    return out, nil
  end
  if type(ok) == "number" then
    code = ok
  end
  code = tonumber(code) or 1
  return nil, ("command failed (exit %d): %s"):format(code, cmd)
end

local function detect_host_os()
  -- Detect OS (windows, linux, macos)
  local sep = package.config:sub(1, 1)
  if sep == "\\" then
    return "windows"
  end

  local uname = io.popen("uname -s", "r"):read("*a") or ""
  if uname:match("Darwin") then
    return "macos"
  elseif uname:match("Linux") then
    return "linux"
  end
  return "unsupported"
end

local function file_exists(path)
  local f = io.open(path, "rb")
  if f then
    f:close()
    return true
  end
  return false
end

local function shell_quote(path, host_os)
  if host_os == "windows" then
    return '"' .. path:gsub('"', '\\"') .. '"'
  end
  -- POSIX shell single-quote escaping: close, escape, reopen.
  return "'" .. path:gsub("'", "'\\''") .. "'"
end

local function first_line(s)
  return (s:gsub("\r", ""):match("([^\n]+)")) or ""
end

local function find_propulse_in_path(host_os)
  if host_os == "windows" then
    local out = capture("where Propulse.exe 2>nul")
    if out then
      local p = trim(first_line(out))
      if p ~= "" then
        return p
      end
    end
    out = capture("where Propulse 2>nul")
    if out then
      local p = trim(first_line(out))
      if p ~= "" then
        return p
      end
    end
    return nil
  end

  local out = capture("command -v Propulse 2>/dev/null")
  if out then
    local p = trim(first_line(out))
    if p ~= "" then
      return p
    end
  end
  return nil
end

local function resolve_propulse(host_os)
  -- Allow override (useful for packaging or when the binary isn't named Propulse)
  local env = os.getenv("PROPULSE")
  if env and trim(env) ~= "" then
    return trim(env)
  end

  -- Prefer current directory (including symlinks)
  if file_exists("./Propulse") then
    return "./Propulse"
  end
  if host_os == "windows" and file_exists("./Propulse.exe") then
    return "./Propulse.exe"
  end

  -- Fall back to PATH
  return find_propulse_in_path(host_os)
end

local host_os = detect_host_os()
if host_os ~= "windows" and host_os ~= "macos" and host_os ~= "linux" then
  io.stderr:write("Unsupported OS\n")
  os.exit(1)
end

local propulse = resolve_propulse(host_os)
if not propulse or trim(propulse) == "" then
  io.stderr:write("Propulse executable not found (current dir or PATH). Set PROPULSE to override.\n")
  os.exit(1)
end

local version_out, version_err = capture(("curl -f -s -L %q"):format(VERSION_URL))
if not version_out then
  io.stderr:write("Failed to download version file\n")
  if version_err then
    io.stderr:write(version_err .. "\n")
  end
  os.exit(1)
end

local latest_version = trim(version_out:gsub("\r", ""))
local build_out, build_err = capture(("%s --build-version"):format(shell_quote(propulse, host_os)))
if not build_out then
  io.stderr:write("Failed to query build version\n")
  if build_err then
    io.stderr:write(build_err .. "\n")
  end
  os.exit(1)
end

local build_version = trim(build_out:gsub("\r", ""))

print("Latest version: " .. latest_version)
print("Build version: " .. build_version)

if build_version ~= latest_version then
  print("Update available")
else
  print("No update available")
end


