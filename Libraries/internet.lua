local internet = {}

function internet.request(url, data, headers, method)
  return unit.call("aio", "internetRequest", url, data, headers, method)
end

function internet.open(address, port)
  return unit.call("aio", "internetConnect", address, port)
end

return internet
