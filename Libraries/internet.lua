local internet = {}
local component_addr = nil

-- Ищем адрес компонента internet
local list = unit.call("aio", "list", "internet")
if list then
  for addr in pairs(list) do
    component_addr = addr
    break
  end
end

if not component_addr then
  return nil -- Нет интернет-карты
end

local proxy = unit.call("aio", "proxy", component_addr)

function internet.request(url, data, headers, method)
  return proxy.request(url, data, headers, method)
end

function internet.open(address, port)
  return proxy.connect(address, port)
end

return internet