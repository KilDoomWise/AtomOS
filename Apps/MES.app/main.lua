local gpu  = require("graphics")
local fs   = require("filesystem")
local auth = require("auth")

auth.initSystem()

local w, h = gpu.getResolution()
local cx, cy = 1, 1
local cwd = "/"
local cmd_history = {}

-- Session state
local current_user = "root"
local hostname     = auth.getHostname()

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

-- Expose print to inline scripts running in this sandbox
_ENV.print = function(...) api.print(...) end

function api.clear()
  gpu.setBackground(0x000000)
  gpu.fill(1, 1, w, h, " ")
  cx, cy = 1, 1
end

function api.getCwd()    return cwd end
function api.setCwd(p)   cwd = p end
function api.getCursor() return cx, cy end
function api.setCursor(x, y) cx, cy = x, y end

function api.getUser()
  return auth.getUser(current_user) or { name = current_user, uid = 0, home = "/root" }
end
function api.setUser(name)
  local u = auth.getUser(name)
  if not u then return false, "no such user" end
  current_user = name
  cwd = u.home
  return true
end
function api.getHome()
  local u = auth.getUser(current_user)
  return u and u.home or "/root"
end
function api.getHostname()    return hostname end
function api.setHostname(name)
  local ok, err = auth.setHostname(name)
  if ok then hostname = name end
  return ok, err
end
function api.isRoot() return current_user == "root" end

-- Blocking line-read used by commands that need interactive input.
-- mask=true replaces typed chars with '*' (for passwords).
function api.readLine(prompt, mask)
  if prompt then
    gpu.setForeground(0xFFFFFF)
    api.write(prompt)
  end
  local sx, sy = cx, cy
  local buf = ""
  local function redraw()
    gpu.setBackground(0x000000)
    gpu.fill(sx, sy, w - sx + 1, 1, " ")
    gpu.setForeground(0xFFFFFF)
    local display = mask and string.rep("*", unicode.len(buf)) or buf
    if #display > 0 then gpu.set(sx, sy, unicode.sub(display, 1, w - sx + 1)) end
    local curX = sx + unicode.len(display)
    gpu.setBackground(0xFFFFFF); gpu.setForeground(0x000000)
    gpu.set(curX, sy, " ")
    gpu.setBackground(0x000000); gpu.setForeground(0xFFFFFF)
  end
  redraw()
  while true do
    local sig = {coroutine.yield()}
    if sig[1] == "key_down" then
      local char, code = sig[3], sig[4]
      if code == 28 then
        gpu.setBackground(0x000000)
        gpu.fill(sx, sy, w - sx + 1, 1, " ")
        local display = mask and string.rep("*", unicode.len(buf)) or buf
        if #display > 0 then gpu.set(sx, sy, display) end
        cx = sx + unicode.len(display); cy = sy
        api.write("\n")
        return buf
      elseif code == 14 and unicode.len(buf) > 0 then
        buf = unicode.sub(buf, 1, -2)
        redraw()
      elseif char >= 32 then
        buf = buf .. unicode.char(char)
        redraw()
      end
    elseif sig[1] == "clipboard" then
      buf = buf .. sig[3]
      redraw()
    end
  end
end
function api.readPassword(prompt) return api.readLine(prompt, true) end

function api.resolve(path)
  -- Pure string normalization — no fs.list() calls.
  -- OC filesystems are case-sensitive so the old case-folding search
  -- was buying nothing except one VFS round-trip per path component.
  local abs = path:sub(1, 1) == "/" and path or (cwd .. "/" .. path)
  local parts = {}
  for part in abs:gmatch("[^/]+") do
    if part == ".." then
      if #parts > 0 then table.remove(parts) end
    elseif part ~= "." then
      parts[#parts + 1] = part
    end
  end
  if #parts == 0 then return "/" end
  return "/" .. table.concat(parts, "/")
end

local cmds = {}
do
  local files = fs.list("/Libraries/MES")
  if files then
    for _, f in ipairs(files) do
      if f:sub(-4) == ".lua" then
        local code = fs.readAll("/Libraries/MES/" .. f)
        if code then
          local fn, lerr = load(code, "=" .. f, "bt", _ENV)
          if fn then
            local ok, result = pcall(fn)
            if ok and type(result) == "function" then
              cmds[f:sub(1, -5)] = result
            end
          end
        end
      end
    end
  end
end

local function complete(buf, pos)
  local line = buf:sub(1, pos)
  local lastSpace = 0
  for i = 1, #line do
    if line:sub(i, i) == " " then lastSpace = i end
  end
  local before  = line:sub(1, lastSpace)
  local word    = line:sub(lastSpace + 1)
  local isFirst = (lastSpace == 0)

  local results = {}
  if word:find("/") then
    local dirPart  = word:match("^(.*/)" ) or ""
    local namePart = word:sub(#dirPart + 1)
    local searchDir = (dirPart ~= "") and api.resolve(dirPart) or cwd
    local list = fs.list(searchDir) or {}
    for _, f in ipairs(list) do
      if #f >= #namePart and f:lower():sub(1, #namePart) == namePart:lower() then
        table.insert(results, dirPart .. f)
      end
    end
  else
    if isFirst then
      for name in pairs(cmds) do
        if #name >= #word and name:lower():sub(1, #word) == word:lower() then
          table.insert(results, name)
        end
      end
    end
    local list = fs.list(cwd) or {}
    for _, f in ipairs(list) do
      local bare = f:gsub("/$", "")
      if #bare >= #word and bare:lower():sub(1, #word) == word:lower() then
        local dup = false
        for _, c in ipairs(results) do
          if c == bare or c == f then dup = true; break end
        end
        if not dup then table.insert(results, f) end
      end
    end
  end

  table.sort(results)
  return results, before, word
end

local function read(promptFn)
  promptFn()

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
        if buf ~= "" then
          cmd_history[#cmd_history + 1] = buf
          if #cmd_history > 100 then table.remove(cmd_history, 1) end
        end
        return buf
      elseif code == 15 then  -- Tab
        local completions, cbefore, cword = complete(buf, pos)
        if #completions == 1 then
          local newWord = completions[1]
          buf = cbefore .. newWord .. buf:sub(pos + 1)
          pos = #cbefore + unicode.len(newWord)
          redraw()
        elseif #completions > 1 then
          local common = completions[1]
          for _, c in ipairs(completions) do
            local i = 1
            while i <= #common and i <= #c and
                  common:sub(i, i):lower() == c:sub(i, i):lower() do
              i = i + 1
            end
            common = common:sub(1, i - 1)
          end
          if unicode.len(common) > unicode.len(cword) then
            buf = cbefore .. common .. buf:sub(pos + 1)
            pos = #cbefore + unicode.len(common)
            redraw()
          else
            -- Show completions, then redraw prompt
            gpu.setBackground(0x000000)
            gpu.setForeground(0xFFFFFF)
            gpu.fill(sx, sy, w - sx + 1, 1, " ")
            gpu.set(sx, sy, buf)
            cx = sx + unicode.len(buf); cy = sy
            api.write("\n")
            local colW = 0
            for _, c in ipairs(completions) do
              if #c > colW then colW = #c end
            end
            colW = colW + 2
            local cols = math.max(1, math.floor(w / colW))
            local col  = 0
            for _, c in ipairs(completions) do
              gpu.setForeground(c:sub(-1) == "/" and 0x4499FF or 0xAAAAAA)
              api.write(string.format("%-" .. colW .. "s", c))
              col = col + 1
              if col >= cols then api.write("\n"); col = 0 end
            end
            if col > 0 then api.write("\n") end
            gpu.setForeground(0xFFFFFF)
            promptFn()
            sx, sy = cx, cy
            redraw()
          end
        end
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
  local input = read(function()
    gpu.setForeground(0x00FFFF)
    local sym = (current_user == "root") and "#" or "$"
    api.write(current_user .. "@" .. hostname .. ":" .. cwd .. sym .. " ")
    gpu.setForeground(0xFFFFFF)
  end)
  local args = {}
  for word in input:gmatch("%S+") do args[#args + 1] = word end

  if #args > 0 then
    local cmd = table.remove(args, 1)
    if cmds[cmd] then
      local ok, err = pcall(cmds[cmd], args, api)
      if not ok then api.print("Error: " .. tostring(err)) end
    else
      -- Try to run as a .lua script (by path or name in cwd)
      local scriptPath
      local resolved = api.resolve(cmd)
      if fs.exists(resolved) and not fs.isDir(resolved) then
        scriptPath = resolved
      else
        local withExt = api.resolve(cmd .. ".lua")
        if fs.exists(withExt) and not fs.isDir(withExt) then
          scriptPath = withExt
        end
      end
      if scriptPath then
        local code = fs.readAll(scriptPath)
        if code then
          local scriptEnv = setmetatable({
            print = function(...) api.print(...) end,
          }, {__index = _ENV})
          local fn, lerr = load(code, "=" .. cmd, "bt", scriptEnv)
          if fn then
            local ok2, runerr = pcall(fn, args, api)
            if not ok2 then api.print("Error: " .. tostring(runerr)) end
          else
            api.print("Syntax error: " .. tostring(lerr))
          end
        else
          api.print(cmd .. ": cannot read file")
        end
      else
        api.print(cmd .. ": command not found")
      end
    end
  end
end