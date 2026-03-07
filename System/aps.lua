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
    -- Block until a real signal arrives (up to 0.05s).
    -- This keeps the computer sleeping between keystrokes instead of
    -- spinning at full speed on pullSignal(0), which wastes energy and
    -- fills the OC event queue with empty ticks.
    local sig = {computer.pullSignal(0.05)}
    if #sig == 0 then
      -- Timeout with no signal: resume tasks once so they can do
      -- housekeeping / animations without any event data.
      for i = #aps.tasks, 1, -1 do
        local t = aps.tasks[i]
        if coroutine.status(t.co) ~= "dead" then
          local ok, err = coroutine.resume(t.co)
          if not ok then atom.panic("Task [" .. t.name .. "]: " .. tostring(err)) end
        else
          table.remove(aps.tasks, i)
        end
      end
    else
      -- Route signal only to tasks that declared interest, or to ALL if no
      -- routing table exists (backward-compatible default).
      for i = #aps.tasks, 1, -1 do
        local t = aps.tasks[i]
        if coroutine.status(t.co) ~= "dead" then
          -- Only wake task if it listens to this signal type, or has no filter.
          local interested = (not t.listen) or t.listen[sig[1]]
          if interested then
            local ok, err = coroutine.resume(t.co, table.unpack(sig))
            if not ok then atom.panic("Task [" .. t.name .. "]: " .. tostring(err)) end
          end
        else
          table.remove(aps.tasks, i)
        end
      end
    end
  end
end

return aps