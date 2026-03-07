local b  = computer.getBootAddress()
local ci = component.invoke

-- Mount table:  mountpoint (string) -> filesystem component address
-- The boot drive is ALWAYS the root "/". No exceptions.
local mounts = { ["/"] = b }

-- Device registry: short_id (5 chars) -> full component address
-- This is NOT the same as mounts — these are known-but-unmounted drives,
-- like /dev/sdb in Linux. You see them in /dev/ but can't read files from
-- them until you explicitly mount them somewhere.
local devices = {}

-- Wrapped file handles: integer id -> { addr, raw_handle }
local handles = {}
local seq = 0

--------------------------------------------------------------------------------
-- Internal helpers
--------------------------------------------------------------------------------

-- Normalize a path: make absolute, resolve . and .., collapse //, strip trailing slash
local function norm(p)
  if not p or p == "" then return "/" end
  if p:sub(1, 1) ~= "/" then p = "/" .. p end
  local parts = {}
  for part in p:gmatch("[^/]+") do
    if part == ".." then
      if #parts > 0 then table.remove(parts) end
    elseif part ~= "." then
      parts[#parts + 1] = part
    end
  end
  if #parts == 0 then return "/" end
  return "/" .. table.concat(parts, "/")
end

-- Populate devices table from all connected filesystem components.
-- Skips the boot drive (always on "/") and the built-in tmpfs RAM disk.
-- Does NOT auto-mount anything — the user must mount explicitly.
local tmp = computer.tmpAddress and computer.tmpAddress() or nil

local function scan()
  devices = {}
  for addr in component.list("filesystem") do
    if addr ~= b and addr ~= tmp then
      local id = addr:sub(1, 5)
      devices[id] = addr
    end
  end
end
scan()

-- Find the best (longest matching) mount point for a path.
-- Returns: component_address, relative_path_on_that_component
local function resolve(p)
  p = norm(p)
  local best, bestLen = "/", 1
  for mp in pairs(mounts) do
    local mlen = #mp
    if mlen > bestLen then
      local match = (p == mp) or
                    (p:sub(1, mlen) == mp and p:sub(mlen + 1, mlen + 1) == "/")
      if match then best = mp; bestLen = mlen end
    end
  end
  local rel = (best == "/") and p or p:sub(#best + 1)
  if rel == "" then rel = "/" end
  return mounts[best], rel
end

-- Virtual /dev/ path helpers
local function isDevPath(p)  return p == "/dev" or p == "/dev/" end
local function devNodeId(p)  return p:match("^/dev/([^/]+)$") end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

local atfs = {}

-- Read-only views of internal state (for mount command etc.)
function atfs.getMounts()  return mounts  end
function atfs.getDevices() return devices end

-- Mount a filesystem component at a mount point.
-- addr can be a full UUID or a 5-char short ID (as listed in /dev/).
function atfs.mount(point, addr)
  if not point or not addr then return false, "invalid args" end
  point = norm(point)
  -- Resolve short ID to full address if needed
  if #addr <= 5 then
    addr = devices[addr]
    if not addr then return false, "unknown device short-id" end
  end
  mounts[point] = addr
  return true
end

-- Unmount a path. Root cannot be unmounted.
function atfs.umount(point)
  point = norm(point)
  if point == "/" then return false, "cannot unmount root" end
  if not mounts[point] then return false, "not a mount point: " .. point end
  mounts[point] = nil
  return true
end

-- Return sorted list of {point, addr, label} for all mounts
function atfs.listMounts()
  local out = {}
  for mp, addr in pairs(mounts) do
    local ok, lbl = pcall(ci, addr, "getLabel")
    table.insert(out, {
      point = mp,
      addr  = addr,
      label = (ok and lbl) or nil,
    })
  end
  table.sort(out, function(a, b2) return a.point < b2.point end)
  return out
end

-- Return sorted list of {id, addr, label} for all known (possibly unmounted) devices
function atfs.listDevices()
  local out = {}
  for id, addr in pairs(devices) do
    local ok, lbl = pcall(ci, addr, "getLabel")
    -- check if already mounted somewhere
    local mountedAt = nil
    for mp, ma in pairs(mounts) do
      if ma == addr then mountedAt = mp; break end
    end
    table.insert(out, {
      id        = id,
      addr      = addr,
      label     = (ok and lbl) or nil,
      mountedAt = mountedAt,
    })
  end
  table.sort(out, function(a, b2) return a.id < b2.id end)
  return out
end

-- Re-scan for connected filesystem components (hot-plug).
-- Mounts are preserved; only the device registry is refreshed.
function atfs.rescan()
  scan()
  return true
end

--------------------------------------------------------------------------------
-- Persistent mounts (fstab)
-- Stored at /System/fstab  — one line per non-root mount:
--   /mountpoint  full-uuid
-- Lines starting with # are comments.
--------------------------------------------------------------------------------

local FSTAB = "/System/fstab"

local function rawRead(path)
  local ok, h = pcall(ci, b, "open", path, "r")
  if not ok or not h then return nil end
  local data = ""
  repeat
    local ok2, chunk = pcall(ci, b, "read", h, math.huge)
    if ok2 and chunk then data = data .. chunk end
  until not (ok2 and chunk)
  pcall(ci, b, "close", h)
  return data
end

local function rawWrite(path, data)
  local ok, h = pcall(ci, b, "open", path, "w")
  if not ok or not h then return false end
  pcall(ci, b, "write", h, data)
  pcall(ci, b, "close", h)
  return true
end

-- Save all non-root mounts to fstab
function atfs.saveFstab()
  local lines = { "# AtomOS fstab - managed automatically, do not edit by hand" }
  for mp, addr in pairs(mounts) do
    if mp ~= "/" then
      table.insert(lines, mp .. " " .. addr)
    end
  end
  return rawWrite(FSTAB, table.concat(lines, "\n") .. "\n")
end

-- Load mounts from fstab (called once at startup)
local function loadFstab()
  local data = rawRead(FSTAB)
  if not data then return end
  for line in (data .. "\n"):gmatch("([^\n]*)\n") do
    line = line:match("^%s*(.-)%s*$")
    if line ~= "" and line:sub(1, 1) ~= "#" then
      local point, addr = line:match("^(%S+)%s+(%S+)$")
      if point and addr then
        mounts[norm(point)] = addr
      end
    end
  end
end
loadFstab()

--------------------------------------------------------------------------------
-- Filesystem operations (VFS layer)
--------------------------------------------------------------------------------

function atfs.exists(p)
  p = norm(p)
  if isDevPath(p)     then return true end
  if devNodeId(p)     then return devices[devNodeId(p)] ~= nil end
  local addr, rel = resolve(p)
  return ci(addr, "exists", rel)
end

function atfs.isDir(p)
  p = norm(p)
  if isDevPath(p)     then return true end
  if devNodeId(p)     then return false end  -- device nodes are not directories
  local addr, rel = resolve(p)
  return ci(addr, "isDirectory", rel)
end

function atfs.list(p)
  p = norm(p)

  -- /dev/ is a virtual directory; list known device short-IDs
  if isDevPath(p) then
    local entries = {}
    for id in pairs(devices) do
      table.insert(entries, id)
    end
    table.sort(entries)
    return entries
  end

  local addr, rel = resolve(p)
  local raw = ci(addr, "list", rel) or {}

  -- Inject virtual "dev/" into the root listing
  if p == "/" then
    local already = false
    for _, e in ipairs(raw) do
      if e == "dev" or e == "dev/" then already = true; break end
    end
    if not already then table.insert(raw, "dev/") end
  end

  -- Inject any active mount points that are direct children of p but
  -- don't physically exist on the underlying disk (like Linux does).
  local pPrefix = (p == "/") and "/" or (p .. "/")
  for mp in pairs(mounts) do
    if mp ~= "/" then
      -- mp must start with pPrefix to be a child
      if mp:sub(1, #pPrefix) == pPrefix then
        local after = mp:sub(#pPrefix + 1)
        -- must be exactly one path segment (no nested slash)
        if after ~= "" and not after:find("/", 1, true) then
          local entry = after .. "/"
          local already = false
          for _, e in ipairs(raw) do
            if e == after or e == entry then already = true; break end
          end
          if not already then table.insert(raw, entry) end
        end
      end
    end
  end

  return raw
end

-- open() returns a wrapped handle integer.
-- All read/write/close calls use that integer, not the raw OC handle.
function atfs.open(p, m)
  p = norm(p)
  if devNodeId(p) then return nil end   -- cannot open a device node directly
  local addr, rel = resolve(p)
  local raw = ci(addr, "open", rel, m or "r")
  if not raw then return nil end
  seq = seq + 1
  handles[seq] = { addr = addr, raw = raw }
  return seq
end

function atfs.read(h, c)
  local info = handles[h]
  if not info then return nil end
  return ci(info.addr, "read", info.raw, c or math.huge)
end

function atfs.write(h, d)
  local info = handles[h]
  if not info then return nil end
  return ci(info.addr, "write", info.raw, d)
end

function atfs.close(h)
  local info = handles[h]
  if not info then return end
  ci(info.addr, "close", info.raw)
  handles[h] = nil
end

function atfs.makeDir(p)
  local addr, rel = resolve(norm(p))
  return ci(addr, "makeDirectory", rel)
end

function atfs.remove(p)
  local addr, rel = resolve(norm(p))
  return ci(addr, "remove", rel)
end

function atfs.readAll(p)
  local h = atfs.open(p, "r")
  if not h then return nil end
  local d = ""
  repeat
    local c = atfs.read(h)
    d = d .. (c or "")
  until not c
  atfs.close(h)
  return d
end

function atfs.writeAll(p, data)
  local h = atfs.open(p, "w")
  if not h then return false, "cannot open: " .. tostring(p) end
  atfs.write(h, data)
  atfs.close(h)
  return true
end

return atfs