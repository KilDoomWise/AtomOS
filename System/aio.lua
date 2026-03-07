local aio = {
  proxies = {}
}

function aio.proxy(addr)
  if not aio.proxies[addr] then
    aio.proxies[addr] = component.proxy(addr)
  end
  return aio.proxies[addr]
end

function aio.list(type)
  return component.list(type)
end

function aio.beep(f, d)
  computer.beep(f, d)
end

function aio.push(name, ...)
  computer.pushSignal(name, ...)
end

function aio.uptime()
  return computer.uptime()
end

function aio.shutdown(reboot)
  computer.shutdown(reboot)
end

function aio.totalMemory()    return computer.totalMemory()  end
function aio.freeMemory()     return computer.freeMemory()   end
function aio.energy()         return computer.energy()        end
function aio.maxEnergy()      return computer.maxEnergy()     end
function aio.getBootAddress() return computer.getBootAddress() end

function aio.componentCount()
  local n = 0
  for _ in component.list() do n = n + 1 end
  return n
end

return aio