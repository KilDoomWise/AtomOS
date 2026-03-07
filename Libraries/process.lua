local proc = {}

function proc.spawn(path) return unit.call("aps", "spawnApp", path) end
function proc.list() return unit.call("aps", "list") end
function proc.kill(id) return unit.call("aps", "kill", id) end

return proc