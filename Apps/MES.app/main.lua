local gpu = require("graphics")
local fs  = require("filesystem")

local w, h = gpu.getResolution()
local cx, cy = 1, 1
local cwd = "/"
local cmd_history = {}

local api = {}

local function scroll_up()
  gpu.copy(1, 2, w, h - 1, 0, -1)
  gpu.setBackground(0x000000)
  gpu.fill(1, h, w, 1, " ")
  cy = h
end

function api.write(txt)
  for i = 1, unicode.len(txt) do
    local ch = unicode.sub(txt, i, i)
    if ch == "\n" then
      cx = 1
      cy = cy + 1
      if cy > h then scroll_up() end
    else
      gpu.set(cx, cy, ch)
      cx = cx + 1
      if cx > w then
        cx = 1
        cy = cy + 1
        if cy > h then scroll_up() end
      end
    end
  end
end

function api.print(...)
  local t = {...}
  for i, v in ipairs(t) do
    t[i] = tostring(v)
  end
  api.write(table.concat(t, "\t") .. "\n")
end

function api.clear()
  gpu.setBackground(0x000000)
  gpu.fill(1, 1, w, h, " ")
  cx, cy = 1, 1
end

function api.getCwd() return cwd end
function api.setCwd(p) cwd = p end

function api.resolve(path)
  local abs = path:sub(1, 1) == "/" and path or (cwd .. "/" .. path)
  local parts = {}
  for part in abs:gmatch("[^/]+") do
    if part == ".." then table.remove(parts)
    elseif part ~= "." then parts[#parts + 1] = part end
  end
  local real = ""
  for _, part in ipairs(parts) do
    local dir = real == "" and "/" or real
    local list = fs.list(dir)
    local found = false
    if list then
      local low = part:lower()
      for _, f in ipairs(list) do
        local clean = f:gsub("/$", "")
        if clean:lower() == low then
          real = real .. "/" .. clean
          found = true
          break
        end
      end
    end
    if not found then real = real .. "/" .. part end
  end
  return real == "" and "/" or real
end

local cmds = {}
local files = fs.list("/Libraries/MES")
if files then
  for _, f in ipairs(files) do
    if f:sub(-4) == ".lua" then
      local code = fs.readAll("/Libraries/MES/" .. f)
      if code then
        local fn = load(code, "=" .. f, "bt", _ENV)
        if fn then cmds[f:sub(1, -5)] = fn() end
      end
    end
  end
end

local function read()
  local buf = ""
  local pos = 0
  local hist_idx = #cmd_history + 1
  local sx, sy = cx, cy

  local function redraw()
    gpu.setBackground(0x000000)
    gpu.fill(sx, sy, w - sx + 1, 1, " ")
    gpu.setForeground(0xFFFFFF)
    gpu.set(sx, sy, unicode.sub(buf, 1, w - sx + 1))
    local cur_x = sx + unicode.len(unicode.sub(buf, 1, pos))
    local ch = unicode.sub(buf, pos + 1, pos + 1)
    if ch == "" then ch = " " end
    gpu.setBackground(0xFFFFFF)
    gpu.setForeground(0x000000)
    gpu.set(cur_x, sy, ch)
    gpu.setBackground(0x000000)
    gpu.setForeground(0xFFFFFF)
  end

  redraw()

  while true do
    local sig = {coroutine.yield()}
    if sig[1] == "key_down" then
      local char, code = sig[3], sig[4]
      if code == 28 then
        gpu.setBackground(0x000000)
        gpu.setForeground(0xFFFFFF)
        gpu.fill(sx, sy, w - sx + 1, 1, " ")
        gpu.set(sx, sy, buf)
        cx = sx + unicode.len(buf)
        cy = sy
        api.write("\n")
        if buf ~= "" then cmd_history[#cmd_history + 1] = buf end
        return buf
      elseif code == 14 then
        if pos > 0 then
          buf = unicode.sub(buf, 1, pos - 1) .. unicode.sub(buf, pos + 1)
          pos = pos - 1
          redraw()
        end
      elseif code == 211 then
        if pos < unicode.len(buf) then
          buf = unicode.sub(buf, 1, pos) .. unicode.sub(buf, pos + 2)
          redraw()
        end
      elseif code == 203 then
        if pos > 0 then pos = pos - 1; redraw() end
      elseif code == 205 then
        if pos < unicode.len(buf) then pos = pos + 1; redraw() end
      elseif code == 200 then
        if hist_idx > 1 then
          hist_idx = hist_idx - 1
          buf = cmd_history[hist_idx]
          pos = unicode.len(buf)
          redraw()
        end
      elseif code == 208 then
        hist_idx = hist_idx + 1
        buf = hist_idx <= #cmd_history and cmd_history[hist_idx] or ""
        pos = unicode.len(buf)
        redraw()
      elseif char >= 32 then
        buf = unicode.sub(buf, 1, pos) .. unicode.char(char) .. unicode.sub(buf, pos + 1)
        pos = pos + 1
        redraw()
      end
    elseif sig[1] == "clipboard" then
      buf = unicode.sub(buf, 1, pos) .. sig[3] .. unicode.sub(buf, pos + 1)
      pos = pos + unicode.len(sig[3])
      redraw()
    end
  end
end

api.clear()
gpu.setForeground(0x00FF00)
api.print("Atom OS v1.0 - MES")
gpu.setForeground(0xFFFFFF)

while true do
  gpu.setForeground(0x00FFFF)
  api.write("root@atom:" .. cwd .. "# ")
  gpu.setForeground(0xFFFFFF)

  local input = read()
  local args = {}
  for word in input:gmatch("%S+") do args[#args + 1] = word end

  if #args > 0 then
    local cmd = table.remove(args, 1)
    if cmds[cmd] then
      local ok, err = pcall(cmds[cmd], args, api)
      if not ok then api.print("Error: " .. tostring(err)) end
    else
      api.print(cmd .. ": command not found")
    end
  end
end