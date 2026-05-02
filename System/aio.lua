local aio = {
  proxies = {},
  internetAddr = nil
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

local function internetProxy()
  if aio.internetAddr then
    local okType, ctype = pcall(component.type, aio.internetAddr)
    if okType and ctype == "internet" then
      return aio.proxy(aio.internetAddr)
    end
    aio.internetAddr = nil
  end
  for addr in component.list("internet") do
    aio.internetAddr = addr
    return aio.proxy(addr)
  end
  return nil, "no_internet_card"
end

function aio.components(filter, exact)
  local out = {}
  for addr, ctype in component.list(filter, exact) do
    local okSlot, slot = pcall(component.slot, addr)
    table.insert(out, {
      addr = addr,
      type = ctype or component.type(addr),
      slot = okSlot and slot or nil
    })
  end
  table.sort(out, function(a, b)
    if a.type == b.type then return a.addr < b.addr end
    return a.type < b.type
  end)
  return out
end

function aio.componentType(addr)
  return component.type(addr)
end

function aio.componentSlot(addr)
  local ok, slot = pcall(component.slot, addr)
  if ok then return slot end
  return nil, slot
end

function aio.methods(addr)
  if not component.methods then return nil, "methods_unavailable" end
  local ok, methods = pcall(component.methods, addr)
  if not ok then return nil, methods end

  local out = {}
  for name, direct in pairs(methods or {}) do
    out[#out + 1] = {name = name, direct = direct and true or false}
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

function aio.doc(addr, method)
  if not component.doc then return nil, "doc_unavailable" end
  local ok, doc = pcall(component.doc, addr, method)
  if ok then return doc end
  return nil, doc
end

function aio.internetRequest(url, data, headers, method)
  local proxy, err = internetProxy()
  if not proxy then return nil, err end
  return proxy.request(url, data, headers, method)
end

function aio.internetConnect(address, port)
  local proxy, err = internetProxy()
  if not proxy then return nil, err end
  return proxy.connect(address, port)
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

function aio.time()
  return os.time()
end

function aio.date(format, time)
  return os.date(format, time)
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
