local g = {}

function g.setResolution(w, h) return unit.call("agpu", "setResolution", w, h) end
function g.getResolution() return unit.call("agpu", "getResolution") end

function g.setBackground(c) return unit.call("agpu", "setBackground", c) end
function g.getBackground() return unit.call("agpu", "getBackground") end

function g.setForeground(c) return unit.call("agpu", "setForeground", c) end
function g.getForeground() return unit.call("agpu", "getForeground") end

function g.fill(x, y, w, h, c) return unit.call("agpu", "fill", x, y, w, h, c) end
function g.set(x, y, v) return unit.call("agpu", "set", x, y, v) end
function g.copy(x, y, w, h, tx, ty) return unit.call("agpu", "copy", x, y, w, h, tx, ty) end

function g.getDepth()      return unit.call("agpu", "getDepth")      end
function g.maxResolution() return unit.call("agpu", "maxResolution") end

function g.getActiveBuffer()        return unit.call("agpu", "getActiveBuffer") end
function g.setActiveBuffer(index)   return unit.call("agpu", "setActiveBuffer", index) end
function g.buffers()                return unit.call("agpu", "buffers") end
function g.allocateBuffer(w, h)     return unit.call("agpu", "allocateBuffer", w, h) end
function g.freeBuffer(index)        return unit.call("agpu", "freeBuffer", index) end
function g.freeAllBuffers()         return unit.call("agpu", "freeAllBuffers") end
function g.totalMemory()            return unit.call("agpu", "totalMemory") end
function g.freeMemory()             return unit.call("agpu", "freeMemory") end
function g.getBufferSize(index)     return unit.call("agpu", "getBufferSize", index) end
function g.bitblt(dst, col, row, w, h, src, fromCol, fromRow)
  return unit.call("agpu", "bitblt", dst, col, row, w, h, src, fromCol, fromRow)
end

function g.hasBufferAPI()
  local active = g.getActiveBuffer()
  return active ~= nil
end

return g
