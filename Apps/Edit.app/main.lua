local _args, _api = ...
local fs = require("filesystem")
local event = require("event")
local gpu = require("graphics")

local state = {
  args = _args, api = _api,
  buffer = {""}, target = nil, isLua = false,
  cx = 1, cy = 1, scrollX = 0, scrollY = 0,
  sel = nil, running = true, modified = false,
  w = 0, h = 0, gutterW = 4, sidebarW = 0,
  findTerm = "", ctrlHeld = false, shiftHeld = false,
  menuActive = nil, menuIdx = 1, itemIdx = 1,
  popup = nil, statusMsg = nil, clipboard = "",
  history = {}, ghostText = nil, lastAction = ""
}

state.w, state.h = gpu.getResolution()

local function requireApp(name)
  local code = fs.readAll("/Apps/Edit.app/" .. name .. ".lua")
  if not code then error("Module not found: " .. name) end
  local chunk, err = load(code, "="..name, "bt", _ENV)
  if not chunk then error("Load error in " .. name .. ": " .. tostring(err)) end
  local builder = chunk()
  return builder(state)
end

state.core   = requireApp("core")
state.syntax = requireApp("syntax")
state.ui     = requireApp("ui")
state.input  = requireApp("input")

state.core.init()
if not state.running then return end

state.ui.init()

while state.running do
  state.ui.drawCursor()
  local sig = {event.pull()}
  state.input.handle(sig)
end

state.ui.clear()