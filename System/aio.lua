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

return aio