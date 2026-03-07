local b = computer.getBootAddress()
local i = component.invoke

local atfs = {}

function atfs.open(p, m) return i(b, "open", p, m or "r") end
function atfs.read(h, c) return i(b, "read", h, c or math.huge) end
function atfs.write(h, d) return i(b, "write", h, d) end
function atfs.close(h) return i(b, "close", h) end
function atfs.exists(p) return i(b, "exists", p) end
function atfs.isDir(p) return i(b, "isDirectory", p) end
function atfs.list(p) return i(b, "list", p) end
function atfs.makeDir(p) return i(b, "makeDirectory", p) end
function atfs.remove(p) return i(b, "remove", p) end

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

return atfs