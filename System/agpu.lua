local agpu = {
  addr = component.list("gpu")(),
  screen = component.list("screen")(),
  i = component.invoke
}

if agpu.addr and agpu.screen then
  agpu.i(agpu.addr, "bind", agpu.screen)
end

function agpu.setResolution(w, h) return agpu.i(agpu.addr, "setResolution", w, h) end
function agpu.getResolution() return agpu.i(agpu.addr, "getResolution") end

function agpu.setBackground(c) return agpu.i(agpu.addr, "setBackground", c) end
function agpu.getBackground() return agpu.i(agpu.addr, "getBackground") end

function agpu.setForeground(c) return agpu.i(agpu.addr, "setForeground", c) end
function agpu.getForeground() return agpu.i(agpu.addr, "getForeground") end

function agpu.fill(x, y, w, h, c) return agpu.i(agpu.addr, "fill", x, y, w, h, c) end
function agpu.set(x, y, v) return agpu.i(agpu.addr, "set", x, y, v) end
function agpu.copy(x, y, w, h, tx, ty) return agpu.i(agpu.addr, "copy", x, y, w, h, tx, ty) end

function agpu.getDepth()       return agpu.i(agpu.addr, "getDepth")        end
function agpu.maxResolution()  return agpu.i(agpu.addr, "maxResolution")   end

return agpu