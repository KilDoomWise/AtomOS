local aps = {
  tasks = {},
  seq = 0,
  ctxSeq = 0,
  ctrlDown = false,
  altDown = false,
  foreground = nil,
  running = nil,
  errors = {}
}

local DEFAULT_CAPS = {
  ["fs.read"] = true,
  ["fs.write"] = true,
  ["fs.inspect"] = true,
  ["gpu"] = true,
  ["sys.info"] = true,
  ["process.spawn"] = true,
  ["process.list"] = true,
  ["process.kill"] = true,
  ["network"] = true,
  ["hardware.inspect"] = true
}

local ROOT_CAPS = { ["*"] = true }

local function copyCaps(src)
  local out = {}
  if src == "*" then
    out["*"] = true
    return out
  end
  for k, v in pairs(src or {}) do
    if type(k) == "number" then out[v] = true
    elseif v then out[k] = true end
  end
  return out
end

local function defaultCaps()
  return copyCaps(DEFAULT_CAPS)
end

local function rootCaps()
  return copyCaps(ROOT_CAPS)
end

local function hasCap(ctx, cap)
  if not cap or cap == true then return true end
  if not ctx then return true end
  if ctx.root or ctx.trusted then return true end
  local caps = ctx.caps or {}
  return caps["*"] or caps[cap] or false
end

local function makeContext(opts, parent, label)
  opts = opts or {}
  parent = parent or {}

  local mayGrant = parent.root or parent.trusted or not parent.user
  if not mayGrant then
    opts.user = parent.user
    opts.uid = parent.uid
    opts.home = parent.home
    opts.root = false
    opts.trusted = false
    opts.system = false
  end
  local user = opts.user or parent.user or "user"
  local uid = opts.uid
  if uid == nil then
    if opts.user and opts.user ~= parent.user then
      uid = (user == "root" and 0 or 1000)
    else
      uid = parent.uid or (user == "root" and 0 or 1000)
    end
  end
  local home = opts.home or parent.home or (uid == 0 and "/root" or ("/home/" .. tostring(user)))
  local requestedRoot = opts.root
  if requestedRoot == nil then requestedRoot = (uid == 0 or user == "root") end

  local root = mayGrant and requestedRoot or (parent.root and uid == 0)
  local trusted = mayGrant and (opts.trusted or opts.system or false) or false
  local caps

  if root or trusted or (mayGrant and opts.caps == "*") then
    caps = rootCaps()
  else
    caps = defaultCaps()
    local requested = copyCaps(opts.caps)
    for cap in pairs(requested) do
      if mayGrant or hasCap(parent, cap) then
        caps[cap] = true
      end
    end
  end

  aps.ctxSeq = aps.ctxSeq + 1
  return {
    id = tostring((parent and parent.taskId) or "ctx") .. ":" .. tostring(aps.ctxSeq),
    taskId = parent.taskId,
    name = label or opts.name or parent.name,
    user = user,
    uid = uid,
    home = home,
    root = root,
    trusted = trusted,
    caps = caps
  }
end

local function currentTask()
  return aps.running
end

local function snapshotContext(ctx)
  if not ctx then return nil end
  return {
    id = ctx.id,
    taskId = ctx.taskId,
    name = ctx.name,
    user = ctx.user,
    uid = ctx.uid,
    home = ctx.home,
    root = ctx.root,
    trusted = ctx.trusted,
    caps = copyCaps(ctx.caps)
  }
end

function aps.currentContext()
  local task = currentTask()
  if not task then
    return {
      id = "kernel",
      taskId = 0,
      name = "kernel",
      user = "root",
      uid = 0,
      home = "/root",
      root = true,
      trusted = true,
      caps = rootCaps()
    }
  end
  return snapshotContext(task.context or task.baseContext)
end

function aps.hasCap(cap)
  return hasCap(aps.currentContext(), cap)
end

function aps.isRoot()
  local ctx = aps.currentContext()
  return ctx and (ctx.root or ctx.trusted or (ctx.caps and ctx.caps["*"])) or false
end

function aps.spawn(path, name, env, priority, opts)
  if type(priority) == "table" and opts == nil then
    opts, priority = priority, nil
  end
  local ok, fn = pcall(atom.load, path, env)
  if not ok then return false, fn end
  if not fn then return false, "load failed: " .. tostring(path) end
  aps.seq = aps.seq + 1
  local parent = aps.currentContext()
  opts = opts or {}
  local taskCtx = makeContext(opts, parent, name or path)
  taskCtx.taskId = aps.seq
  taskCtx.id = tostring(aps.seq) .. ":base"
  local task = {
    co = coroutine.create(fn),
    name = name or path,
    prio = priority or 1,
    started = aps.seq,
    tid = aps.seq,
    baseContext = taskCtx,
    context = taskCtx,
    contextStack = {}
  }
  table.insert(aps.tasks, task)
  
  table.sort(aps.tasks, function(a, b) return a.prio < b.prio end)
  
  return true
end

function aps.spawnApp(appPath, priority, opts)
  if type(priority) == "table" and opts == nil then
    opts, priority = priority, nil
  end
  local mainPath = appPath .. "/main.lua"
  local fs = atom.ring1.atfs
  if not fs.exists(mainPath) then return false, "main.lua not found" end
  local name = appPath:match("([^/]+)%.app/?$") or appPath
  local clean_env = atom.ring1.env.create()
  return aps.spawn(mainPath, name, clean_env, priority, opts)
end

function aps.list()
  local info = {}
  for i, t in ipairs(aps.tasks) do
    local ctx = t.context or t.baseContext or {}
    table.insert(info, {
      id = i,
      tid = t.tid,
      name = t.name,
      status = coroutine.status(t.co),
      prio = t.prio,
      user = ctx.user or "?",
      root = ctx.root and true or false
    })
  end
  return info
end

function aps.kill(id)
  local target = aps.tasks[id]
  if target then
    local caller = aps.currentContext()
    if target == aps.running then
      return false, "cannot kill current task"
    end
    local targetCtx = target.context or target.baseContext or {}
    if caller and not hasCap(caller, "*") and not caller.root and not caller.trusted then
      if caller.taskId ~= target.tid and caller.uid ~= targetCtx.uid then
        return false, "permission denied"
      end
    end
    if aps.foreground and aps.foreground.owner == target then
      aps.foreground = nil
    end
    table.remove(aps.tasks, id)
    return true
  end
  return false, "not_found"
end

function aps.enterForeground(name, opts)
  local owner = aps.running
  if not owner then return nil, "no running task" end
  local parent = owner.context or owner.baseContext
  local token = {}
  owner.contextStack = owner.contextStack or {}
  table.insert(owner.contextStack, {
    context = owner.context,
    foreground = aps.foreground
  })
  owner.context = makeContext(opts or {}, parent, name)
  owner.context.taskId = owner.tid
  owner.context.leaveToken = token
  aps.foreground = {
    name = name,
    owner = owner,
    token = token
  }
  return token
end

function aps.leaveForeground(token)
  local owner = aps.running
  if not owner or not owner.context then return false, "no running task" end
  if owner.context.leaveToken ~= token then
    return false, "bad foreground token"
  end
  local prev = table.remove(owner.contextStack or {})
  owner.context = prev and prev.context or owner.baseContext
  aps.foreground = prev and prev.foreground or nil
  return true
end

local function isCtrl(code)
  return code == 29 or code == 157
end

local function isAlt(code)
  return code == 56 or code == 184
end

local function isInterruptKey(char, code)
  return code == 46 or char == 3 or char == 67 or char == 99
end

local function updateModifiers(sig)
  local event, char, code = sig[1], sig[3], sig[4]
  if event == "key_down" then
    if isCtrl(code) then aps.ctrlDown = true end
    if isAlt(code) then aps.altDown = true end
    return aps.ctrlDown and aps.altDown and isInterruptKey(char, code)
  elseif event == "key_up" then
    if isCtrl(code) then aps.ctrlDown = false end
    if isAlt(code) then aps.altDown = false end
  end
  return false
end

local function renderFatalTaskError(item)
  local gpu = atom.ring1 and atom.ring1.agpu
  if not gpu then return end

  pcall(function()
    local w, h = gpu.getResolution()
    gpu.setBackground(0x000000)
    gpu.setForeground(0xFF5555)
    gpu.fill(1, 1, w, h, " ")
    gpu.set(2, 2, "SYSTEM TASK CRASHED: " .. tostring(item.name or "unknown"))
    gpu.setForeground(0xFFFFFF)
    gpu.set(2, 4, tostring(item.error or "unknown error"))

    local y = 6
    for line in (tostring(item.traceback or "") .. "\n"):gmatch("([^\n]*)\n") do
      if y > h then break end
      gpu.set(2, y, line:sub(1, w - 2))
      y = y + 1
    end
  end)
end

local function resumeTask(t, ...)
  aps.running = t
  local ok, err = coroutine.resume(t.co, ...)
  aps.running = nil
  if not ok then
    local trace = tostring(err)
    if debug and debug.traceback then
      local tok, tb = pcall(debug.traceback, t.co, tostring(err))
      if tok and tb then trace = tb end
    end

    local item = {
      name = t.name,
      error = tostring(err),
      traceback = trace
    }
    aps.errors[#aps.errors + 1] = item
    while #aps.errors > 16 do table.remove(aps.errors, 1) end
    if t.name == "MES" then renderFatalTaskError(item) end
    return false
  end
  return true
end

local function removeDeadTask(i)
  local task = aps.tasks[i]
  if aps.foreground and aps.foreground.owner == task then
    aps.foreground = nil
  end
  table.remove(aps.tasks, i)
end

local function interruptForeground()
  local fg = aps.foreground
  if not fg or not fg.owner then return false end
  if coroutine.status(fg.owner.co) == "dead" then
    aps.foreground = nil
    return false
  end
  local ok = resumeTask(fg.owner, "atom_interrupt", fg.name)
  if not ok then
    for i, t in ipairs(aps.tasks) do
      if t == fg.owner then
        removeDeadTask(i)
        break
      end
    end
  end
  return true
end

local function killLatestBackground()
  local targetIdx, newest = nil, -1
  for i, t in ipairs(aps.tasks) do
    if t.name ~= "MES" and coroutine.status(t.co) ~= "dead" and (t.started or 0) > newest then
      targetIdx, newest = i, t.started or 0
    end
  end
  if targetIdx then
    table.remove(aps.tasks, targetIdx)
    return true
  end
  return false
end

function aps.interrupt()
  if interruptForeground() then return true end
  return killLatestBackground()
end

function aps.popError()
  if #aps.errors == 0 then return nil end
  return table.remove(aps.errors, 1)
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
          if not resumeTask(t) or coroutine.status(t.co) == "dead" then
            removeDeadTask(i)
          end
        else
          removeDeadTask(i)
        end
      end
    else
      if updateModifiers(sig) then
        aps.interrupt()
      else
        -- Route signal only to tasks that declared interest, or to ALL if no
        -- routing table exists (backward-compatible default).
        for i = #aps.tasks, 1, -1 do
          local t = aps.tasks[i]
          if coroutine.status(t.co) ~= "dead" then
            -- Only wake task if it listens to this signal type, or has no filter.
            local interested = (not t.listen) or t.listen[sig[1]]
            if interested then
              if not resumeTask(t, table.unpack(sig)) or coroutine.status(t.co) == "dead" then
                removeDeadTask(i)
              end
            end
          else
            removeDeadTask(i)
          end
        end
      end
    end
  end
end

return aps
