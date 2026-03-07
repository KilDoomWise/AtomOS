local io = {}

function io.list(type) return unit.call("aio", "list", type) end
function io.beep(f, d) return unit.call("aio", "beep", f, d) end
function io.push(name, ...) return unit.call("aio", "push", name, ...) end
function io.uptime() return unit.call("aio", "uptime") end
function io.shutdown(reboot) return unit.call("aio", "shutdown", reboot) end

return io