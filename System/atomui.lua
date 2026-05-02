local node = {
  path = "/etc/atomui.cfg",
  drivers = {}
}

local defaults = {
  autostart = false,
  width = 160,
  height = 50
}

local function atfs()
  return atom and atom.ring1 and atom.ring1.atfs
end

local function parseValue(value)
  value = tostring(value or "")
  if value == "true" then return true end
  if value == "false" then return false end
  local number = tonumber(value)
  if number ~= nil then return number end
  return value
end

local function serializeValue(value)
  if type(value) == "boolean" then return value and "true" or "false" end
  return tostring(value)
end

function node.getConfig()
  local cfg = {}
  for k, v in pairs(defaults) do cfg[k] = v end

  local fs = atfs()
  if not fs then return cfg end
  local data = fs.readAll(node.path)
  if data then
    for line in tostring(data):gmatch("[^\r\n]+") do
      local key, value = line:match("^([%w_%.%-]+)%s*=%s*(.-)%s*$")
      if key then cfg[key] = parseValue(value) end
    end
  end
  return cfg
end

function node.setConfig(nextCfg)
  local cfg = node.getConfig()
  for k, v in pairs(nextCfg or {}) do cfg[k] = v end

  local fs = atfs()
  if not fs then return false, "atfs_unavailable" end
  if not fs.exists("/etc") then fs.makeDir("/etc") end

  local keys = {}
  for k in pairs(cfg) do keys[#keys + 1] = k end
  table.sort(keys)

  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = k .. "=" .. serializeValue(cfg[k]) end
  return fs.writeAll(node.path, table.concat(out, "\n") .. "\n")
end

function node.get(key)
  return node.getConfig()[key]
end

function node.set(key, value)
  return node.setConfig({[key] = value})
end

function node.announce(name, info)
  name = tostring(name or "")
  if name == "" then return false, "bad_name" end
  node.drivers[name] = {
    name = name,
    info = info or {},
    seen = os.time()
  }
  return true
end

function node.listDrivers()
  local out = {}
  for name, item in pairs(node.drivers) do
    out[#out + 1] = {
      name = name,
      info = item.info,
      seen = item.seen
    }
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

function node.status()
  return {
    online = true,
    config = node.getConfig(),
    drivers = node.listDrivers()
  }
end

return function()
  node.setConfig(node.getConfig())
  return node
end
