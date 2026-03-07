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

return g