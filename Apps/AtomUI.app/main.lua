local _args, _api = ...

local fs    = require("filesystem")
local gpu   = require("graphics")
local event = require("event")

local APP_PATH = "/Apps/AtomUI.app"

local state = {
  args = _args or {},
  api = _api,
  appPath = APP_PATH,
  running = true,
  w = 0,
  h = 0
}

local function requireApp(name)
  local path = APP_PATH .. "/" .. name .. ".lua"
  local code = fs.readAll(path)
  if not code then error("AtomUI module not found: " .. name) end

  local chunk, loadErr = load(code, "=" .. path, "bt", _ENV)
  if not chunk then
    error("AtomUI module load failed: " .. name .. ": " .. tostring(loadErr))
  end

  local ok, builder = pcall(chunk)
  if not ok then
    error("AtomUI module init failed: " .. name .. ": " .. tostring(builder))
  end

  if type(builder) == "function" then
    return builder(state)
  end
  return builder
end

local function atomConfig()
  if unit and unit.call then
    local ok, cfg = pcall(unit.call, "atomui", "getConfig")
    if ok and type(cfg) == "table" then return cfg end
  end
  local data = fs.readAll("/etc/atomui.cfg")
  local cfg = {}
  if data then
    for line in tostring(data):gmatch("[^\r\n]+") do
      local key, value = line:match("^([%w_%.%-]+)%s*=%s*(.-)%s*$")
      if key then
        if value == "true" then cfg[key] = true
        elseif value == "false" then cfg[key] = false
        else cfg[key] = tonumber(value) or value end
      end
    end
  end
  return cfg
end

state.theme  = requireApp("theme")
state.screen = requireApp("buffer")
state.widgets = requireApp("widgets")
state.windows = requireApp("windows")
state.launcher = requireApp("launcher")
state.desktop = requireApp("desktop")

local function setupResolution()
  local maxW, maxH = gpu.maxResolution()
  maxW, maxH = maxW or 80, maxH or 25
  state.maxW, state.maxH = maxW, maxH

  local cfg = atomConfig()
  local wantW = tonumber(cfg.width) or state.theme.layout.maxW
  local wantH = tonumber(cfg.height) or state.theme.layout.maxH
  state.w = math.min(wantW, maxW)
  state.h = math.min(wantH, maxH)
  if state.w < 60 then state.w = maxW end
  if state.h < 20 then state.h = maxH end

  gpu.setResolution(state.w, state.h)
  state.screen.resize(state.w, state.h)
end

function state.applyResolution(w, h)
  local maxW, maxH = gpu.maxResolution()
  state.maxW, state.maxH = maxW, maxH
  state.w = math.max(60, math.min(maxW or 160, tonumber(w) or state.w))
  state.h = math.max(20, math.min(maxH or 50, tonumber(h) or state.h))
  gpu.setResolution(state.w, state.h)
  state.screen.resize(state.w, state.h)
  if state.windows and state.windows.reflow then state.windows.reflow() end
  if state.desktop then state.desktop.invalidateAll() end
end

setupResolution()
state.desktop.init()

while state.running do
  state.desktop.renderDirty()
  state.screen.flush()

  local sig = {event.pull(0.25)}
  state.desktop.handle(sig)
  state.desktop.tick()
end

state.desktop.shutdown()
state.desktop.renderDirty()
state.screen.flush()
