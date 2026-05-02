local node = {}

function node.getConfig()
  return unit.call("atomui", "getConfig")
end

function node.setConfig(cfg)
  return unit.call("atomui", "setConfig", cfg)
end

function node.get(key)
  return unit.call("atomui", "get", key)
end

function node.set(key, value)
  return unit.call("atomui", "set", key, value)
end

function node.status()
  return unit.call("atomui", "status")
end

function node.announce(name, info)
  return unit.call("atomui", "announce", name, info)
end

function node.listDrivers()
  return unit.call("atomui", "listDrivers")
end

return node
