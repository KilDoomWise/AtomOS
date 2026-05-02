local unit = {}
local r1 = _G.atom.ring1

local function isWriteMode(mode)
  mode = tostring(mode or "r")
  return mode:find("w", 1, true) or mode:find("a", 1, true)
end

local POLICY = {
  atfs = {
    exists = "fs.read",
    isDir = "fs.read",
    list = "fs.read",
    open = function(_, mode) return isWriteMode(mode) and "fs.write" or "fs.read" end,
    read = "fs.read",
    readAll = "fs.read",
    close = true,
    write = "fs.write",
    writeAll = "fs.write",
    makeDir = "fs.write",
    remove = "fs.write",
    listMounts = "fs.inspect",
    listDevices = "fs.inspect",
    getMounts = "fs.mount",
    getDevices = "fs.mount",
    mount = "fs.mount",
    umount = "fs.mount",
    rescan = "fs.mount",
    saveFstab = "fs.mount"
  },
  agpu = {
    setResolution = "gpu",
    getResolution = "gpu",
    setBackground = "gpu",
    getBackground = "gpu",
    setForeground = "gpu",
    getForeground = "gpu",
    fill = "gpu",
    set = "gpu",
    copy = "gpu",
    getDepth = "gpu",
    maxResolution = "gpu",
    getActiveBuffer = "gpu",
    setActiveBuffer = "gpu",
    buffers = "gpu",
    allocateBuffer = "gpu",
    freeBuffer = "gpu",
    freeAllBuffers = "gpu",
    totalMemory = "gpu",
    freeMemory = "gpu",
    getBufferSize = "gpu",
    bitblt = "gpu"
  },
  aio = {
    uptime = "sys.info",
    time = "sys.info",
    date = "sys.info",
    totalMemory = "sys.info",
    freeMemory = "sys.info",
    energy = "sys.info",
    maxEnergy = "sys.info",
    componentCount = "sys.info",
    getBootAddress = "sys.info",
    beep = "sys.info",
    components = "hardware.inspect",
    componentType = "hardware.inspect",
    componentSlot = "hardware.inspect",
    methods = "hardware.inspect",
    doc = "hardware.inspect",
    internetRequest = "network",
    internetConnect = "network",
    list = "hardware.raw",
    proxy = "hardware.raw",
    push = "signal.push",
    shutdown = "power"
  },
  aps = {
    spawn = "process.raw",
    spawnApp = "process.spawn",
    list = "process.list",
    kill = "process.kill",
    enterForeground = true,
    leaveForeground = true,
    interrupt = "process.interrupt",
    popError = true,
    currentContext = true,
    hasCap = true,
    isRoot = true
  },
  atomui = {
    getConfig = "sys.info",
    get = "sys.info",
    status = "sys.info",
    listDrivers = "sys.info",
    announce = true,
    setConfig = "fs.write",
    set = "fs.write"
  }
}

local function canCall(svc, fn, ...)
  local policy = POLICY[svc]
  local need = nil

  if policy == true then
    return true
  elseif type(policy) == "table" then
    need = policy[fn]
  end

  if type(need) == "function" then
    need = need(...)
  end

  if need == nil then
    return false, "access_denied:" .. tostring(svc) .. "." .. tostring(fn)
  end
  if need == true then return true end

  local aps = r1.aps
  if not aps or not aps.hasCap then return true end
  if aps.hasCap(need) then return true end

  return false, "access_denied:" .. tostring(need)
end

function unit.call(svc, fn, ...)
  if not r1[svc] then 
    return nil, "svc_not_found" 
  end
  if type(r1[svc][fn]) ~= "function" then 
    return nil, "fn_not_found" 
  end
  local allowed, reason = canCall(svc, fn, ...)
  if not allowed then
    return nil, reason
  end
  
  local ok, res1, res2, res3 = pcall(r1[svc][fn], ...)
  if not ok then
    return nil, res1
  end
  return res1, res2, res3
end

return unit
