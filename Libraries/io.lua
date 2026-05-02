local io = {}

function io.list(type)       return unit.call("aio", "list", type)       end
function io.beep(f, d)       return unit.call("aio", "beep", f, d)       end
function io.push(name, ...)  return unit.call("aio", "push", name, ...)  end
function io.uptime()         return unit.call("aio", "uptime")           end
function io.time()           return unit.call("aio", "time")             end
function io.date(f, t)       return unit.call("aio", "date", f, t)       end
function io.shutdown(reboot) return unit.call("aio", "shutdown", reboot) end

function io.totalMemory()    return unit.call("aio", "totalMemory")    end
function io.freeMemory()     return unit.call("aio", "freeMemory")     end
function io.energy()         return unit.call("aio", "energy")         end
function io.maxEnergy()      return unit.call("aio", "maxEnergy")      end
function io.componentCount() return unit.call("aio", "componentCount") end

return io
