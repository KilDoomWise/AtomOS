local b = computer.getBootAddress()
local i = component.invoke

local function sys_load(f, env)
  local h = assert(i(b, "open", f))
  local d = ""
  repeat
    local c = i(b, "read", h, math.maxinteger or 9999999)
    d = d .. (c or "")
  until not c
  i(b, "close", h)
  return assert(load(d, "=" .. f, "bt", env or _ENV))
end

sys_load("/System/kernel.lua")(sys_load)