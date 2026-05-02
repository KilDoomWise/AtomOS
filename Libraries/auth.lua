local fs = require("filesystem")

local PASSWD   = "/etc/passwd"
local HOSTNAME = "/etc/hostname"

local auth = {}

-- djb2 hash (Lua 5.3 bitwise ops)
local function hash(s)
  if not s or s == "" then return "" end
  local h = 5381
  for i = 1, #s do
    h = ((h * 33) ~ string.byte(s, i)) & 0xFFFFFFFF
  end
  return string.format("%08x", h)
end
auth.hash = hash

--------------------------------------------------------------------------------
-- /etc/passwd  →  username:passwordhash:uid:homedir
--------------------------------------------------------------------------------

local function readPasswd()
  local users = {}
  if not fs.exists(PASSWD) then return users end
  local data = fs.readAll(PASSWD) or ""
  for line in (data .. "\n"):gmatch("([^\n]*)\n") do
    line = line:match("^%s*(.-)%s*$")
    if line ~= "" and line:sub(1, 1) ~= "#" then
      local name, ph, uid, home = line:match("^([^:]+):([^:]*):([^:]*):([^:]*)$")
      if name then
        table.insert(users, { name = name, hash = ph, uid = tonumber(uid) or 0, home = home })
      end
    end
  end
  return users
end

local function writePasswd(users)
  local lines = { "# AtomOS passwd" }
  for _, u in ipairs(users) do
    table.insert(lines, u.name .. ":" .. (u.hash or "") .. ":" .. u.uid .. ":" .. u.home)
  end
  return fs.writeAll(PASSWD, table.concat(lines, "\n") .. "\n")
end

function auth.getUsers() return readPasswd() end

function auth.getUser(name)
  for _, u in ipairs(readPasswd()) do
    if u.name == name then return u end
  end
  return nil
end

-- Returns true when password is correct (empty hash = no password set)
function auth.verify(name, password)
  local u = auth.getUser(name)
  if not u then return false end
  if u.hash == "" then return true end
  return u.hash == hash(password)
end

-- Create new user. uid auto-assigned if nil. Returns true or false, err.
function auth.addUser(name, password, uid, home)
  if not name:match("^[a-z_][a-z0-9_%-]*$") then
    return false, "invalid username (a-z, 0-9, _ - only)"
  end
  local users = readPasswd()
  for _, u in ipairs(users) do
    if u.name == name then return false, "user already exists" end
  end
  if not uid then
    local max = 999
    for _, u in ipairs(users) do if u.uid > max then max = u.uid end end
    uid = max + 1
  end
  home = home or ("/home/" .. name)
  table.insert(users, { name = name, hash = hash(password or ""), uid = uid, home = home })
  local ok, err = writePasswd(users)
  if not ok then return false, err end
  if not fs.exists(home) then
    ok, err = fs.makeDir(home)
    if not ok then return false, err end
  end
  return true
end

function auth.delUser(name)
  if name == "root" then return false, "cannot delete root" end
  local users = readPasswd()
  local new, found = {}, false
  for _, u in ipairs(users) do
    if u.name == name then found = true
    else table.insert(new, u) end
  end
  if not found then return false, "user not found" end
  return writePasswd(new)
end

function auth.setPassword(name, password)
  local users = readPasswd()
  for _, u in ipairs(users) do
    if u.name == name then
      u.hash = hash(password or "")
      return writePasswd(users)
    end
  end
  return false, "user not found"
end

--------------------------------------------------------------------------------
-- /etc/hostname
--------------------------------------------------------------------------------

function auth.getHostname()
  if not fs.exists(HOSTNAME) then return "atom" end
  return (fs.readAll(HOSTNAME) or "atom"):match("^%s*(.-)%s*$")
end

function auth.setHostname(name)
  if not name or name == "" then return false, "empty hostname" end
  return fs.writeAll(HOSTNAME, name .. "\n")
end

--------------------------------------------------------------------------------
-- First-boot initialisation
--------------------------------------------------------------------------------

function auth.initSystem()
  for _, dir in ipairs({ "/etc", "/root", "/home" }) do
    if not fs.exists(dir) then fs.makeDir(dir) end
  end
  if not fs.exists(HOSTNAME) then
    fs.writeAll(HOSTNAME, "atom\n")
  end
  if not fs.exists(PASSWD) then
    fs.writeAll(PASSWD, "# AtomOS passwd\nroot::0:/root\n")
  end
end

return auth
