local env = {}
local u = atom.load("/System/unit.lua")()

function env.create()
  local e = {}
  e.unit = u
  e.math = math
  e.string = string
  e.table = table
  e.coroutine = coroutine
  e.unicode = unicode
  e.tonumber = tonumber
  e.tostring = tostring
  e.type = type
  e.pcall = pcall
  e.xpcall = xpcall
  e.assert = assert
  e.error = error
  e.pairs = pairs
  e.ipairs = ipairs
  e.next = next
  e.select = select
  e.load = load
  e.setmetatable = setmetatable
  e.getmetatable = getmetatable
  e.rawget = rawget
  e.rawset = rawset
  e.rawequal = rawequal
  e.rawlen = rawlen
  e._G = e

  e.require = function(path)
    local code = u.call("atfs", "readAll", "/Libraries/" .. path .. ".lua")
    if not code then e.error("Library not found: " .. path) end
    local fn = assert(load(code, "=" .. path, "bt", e))
    return fn()
  end
  
  return e
end

return env