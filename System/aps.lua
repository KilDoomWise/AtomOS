local aps = {
  tasks = {}
}

function aps.spawn(path, name, env, priority)
  local fn, err = atom.load(path, env)
  if not fn then return false, err end
  local task = {
    co = coroutine.create(fn),
    name = name or path,
    prio = priority or 1
  }
  table.insert(aps.tasks, task)
  
  table.sort(aps.tasks, function(a, b) return a.prio < b.prio end)
  
  return true
end

function aps.spawnApp(appPath, priority)
  local mainPath = appPath .. "/main.lua"
  local fs = atom.ring1.atfs
  if not fs.exists(mainPath) then return false, "main.lua not found" end
  local name = appPath:match("([^/]+)%.app/?$") or appPath
  local clean_env = atom.ring1.env.create()
  return aps.spawn(mainPath, name, clean_env, priority)
end

function aps.list()
  local info = {}
  for i, t in ipairs(aps.tasks) do
    table.insert(info, {id = i, name = t.name, status = coroutine.status(t.co), prio = t.prio})
  end
  return info
end

function aps.kill(id)
  if aps.tasks[id] then
    table.remove(aps.tasks, id)
    return true
  end
  return false, "not_found"
end

function aps.start()
  while true do
    local sig = {computer.pullSignal(0)}
    local has_active = false

    for i = #aps.tasks, 1, -1 do
      local t = aps.tasks[i]
      if coroutine.status(t.co) ~= "dead" then
        has_active = true
        local ok, err = coroutine.resume(t.co, table.unpack(sig))
        if not ok then
          atom.panic("Task [" .. t.name .. "]: " .. tostring(err))
        end
      else
        table.remove(aps.tasks, i)
      end
    end

    if not has_active and #sig == 0 then
      computer.pullSignal(0.05)
    end
  end
end

return aps