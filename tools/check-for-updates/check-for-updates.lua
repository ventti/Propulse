-- check-for-updates.lua
--
-- Replaces tools/scripts/check-for-updates.sh with a pure-Lua implementation
-- intended to be compiled into a small executable via luastatic.
--
-- Notes:
-- - Uses the system's `curl` command (same as the shell script did).
-- - Expects Propulse binary in the current working directory.

local download_urls = {
  version = "https://www.dropbox.com/scl/fi/qls23vtmsb1bff3jjjhwx/version.txt?rlkey=og28di232duaelbg8ak2xn74t&st=o6h9f6qz&dl=0",
  changelog = "https://www.dropbox.com/scl/fi/kwfkl3blvbgdqb4f6vep9/CHANGELOG.txt?rlkey=lvqtjc3ylu5pyc4prk0xgc127&st=7o2v4uqh&dl=0",
  macos = "https://www.dropbox.com/scl/fi/8sr2bxp28hqjs8h20thgn/Propulse-macos-arm64.zip?rlkey=aoqayuuqo06cbirw0ov63wrj0&st=rp8dylaq&dl=0",
  windows = "https://www.dropbox.com/scl/fi/e5r7ztjkgzlzrihkgljgn/Propulse-windows-x64.zip?rlkey=p8uu5sqai1lyonnq5w7oqhkgc&st=83smgsxb&dl=0",
  linux = nil -- Not implemented, placeholder
}

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

local version_out, version_err = capture(("curl -f -s -L %q"):format(download_urls.version))
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

local function split_semver(version)
  local out = {}
  local major, minor, patch = version:match("^(%d+)%.(%d+)%.(%d+)$")
  out["major"] = tonumber(major)
  out["minor"] = tonumber(minor)
  out["patch"] = tonumber(patch)  
  return out
end


local function split_gitdescribe(gitdescribe)
  -- Returns a table with:
  --   version: "X.Y.Z" | nil
  --   since: "N" | nil               (commits since version tag)
  --   hash: "abcdef1" | nil          (git hash from git-describe or plain hash)
  --   dirty: boolean
  -- Handles:
  --   X.Y.Z
  --   X.Y.Z-dirty
  --   X.Y.Z-N-gHASH
  --   X.Y.Z-N-gHASH-dirty
  --   HASH
  --   HASH-dirty
  local s = trim((gitdescribe or ""):gsub("\r", ""))
  local out = { version = {}, since = nil, hash = nil, dirty = false }
  -- Version tag cases
  do
    local v, since, h = s:match("^(%d+%.%d+%.%d+)%-(%d+)%-g([0-9a-fA-F]+)$")

    if v then
      out.version = split_semver(v)
      out.since = tonumber(since)
      out.hash = h
      return out
    end
  end

  do
    local v = s:match("^(%d+%.%d+%.%d+)$")
    if v then
      out.version.major, out.version.minor, out.version.patch = split_semver(v)
      return out
    end
  end

  -- Hash-only case
  do
    local h = s:match("^([0-9a-fA-F]+)$")
    if h and #h >= 7 then
      out.hash = h
      return out
    end
  end

  -- Unknown/unsupported format: leave fields nil/false.
  return out
end

local function is_later_gitdescribe_than(a, b)
  if a == b then
    return 0
  end
  local split_a = split_gitdescribe(a)
  local split_b = split_gitdescribe(b)

  if split_a.version.major > split_b.version.major then return 1 end
  if split_a.version.major < split_b.version.major then return -1 end
  if split_a.version.minor > split_b.version.minor then return 1 end
  if split_a.version.minor < split_b.version.minor then return -1 end
  if split_a.version.patch > split_b.version.patch then return 1 end
  if split_a.version.patch < split_b.version.patch then return -1 end

  if split_a.since > split_b.since then return 1 end
  if split_a.since < split_b.since then return -1 end
  if split_a.hash ~= split_b.hash then return nil end
  if split_a.dirty and not split_b.dirty then return 1 end -- a is newer than b
  if not split_a.dirty and split_b.dirty then return -1 end  -- b is newer than a
  if split_a.dirty and split_b.dirty then return nil end  -- both dirty, unknown changes
  return 0
end

local function is_dirty(version)
  -- substring
  local dirty = version:sub(-5) == "-dirty"
  return dirty
end

local is_later = is_later_gitdescribe_than(latest_version, build_version)
if is_dirty(latest_version) then
  print("WARNING: Latest version is dirty: " .. latest_version)
end
if is_dirty(build_version) then
  print("WARNING: Latest version is dirty: " .. latest_version)
end

local function download_latest_version()
  local download_url = download_urls[host_os]
  local download_out, download_err = capture(("curl -f -s -o Propulse-%q.zip -L %q"):format(latest_version, download_url))
  if not download_out then
    io.stderr:write("Failed to download latest version\n")
    if download_err then
      io.stderr:write("Failed to download latest version: " .. download_err .. "\n")
      os.exit(1)
    end
  end
end

if table.contains(arg, "--update") or table.contains(arg, "-u") then
  local can_update = true
end
if table.contains(arg, "--force") or table.contains(arg, "-f") then
  local do_update = true
end
if is_later == 1 then
  print("Update available: " .. build_version .. " -> " .. latest_version)
  if can_update then
    do_update = true
  else
    print("Update available, run with --update or -u to update")
  end
elseif is_later == -1 then
  print("No update available: " .. build_version .. " is newer than " .. latest_version)
else
  print("No update available: already got the latest version (" .. build_version .. ")")
end

if do_update then download_latest_version() end
