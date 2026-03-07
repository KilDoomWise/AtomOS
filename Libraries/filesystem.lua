local fs = {}

function fs.open(p, m) return unit.call("atfs", "open", p, m) end
function fs.read(h, c) return unit.call("atfs", "read", h, c) end
function fs.write(h, d) return unit.call("atfs", "write", h, d) end
function fs.close(h) return unit.call("atfs", "close", h) end
function fs.exists(p) return unit.call("atfs", "exists", p) end
function fs.isDir(p) return unit.call("atfs", "isDir", p) end
function fs.list(p) return unit.call("atfs", "list", p) end
function fs.makeDir(p) return unit.call("atfs", "makeDir", p) end
function fs.remove(p) return unit.call("atfs", "remove", p) end
function fs.readAll(p)      return unit.call("atfs", "readAll",  p)       end
function fs.writeAll(p, d)  return unit.call("atfs", "writeAll", p, d)     end

return fs