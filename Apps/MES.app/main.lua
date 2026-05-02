local gpu  = require("graphics")
local fs   = require("filesystem")
local auth = require("auth")
local diagnostics = require("diagnostics")

auth.initSystem()

local w, h = gpu.getResolution()
local cx, cy = 1, 1
local cwd = "/"
local cmd_history = {}
local MAX_SCROLLBACK = 200
local BG, FG = 0x000000, 0xFFFFFF

-- Session state
local current_user = "root"
local hostname     = auth.getHostname()

local api = {}
local SESSION_TOKEN = {}

local term_lines = {
  { text = "", runs = {} }
}
local view_offset = 0

local function new_line()
  term_lines[#term_lines + 1] = { text = "", runs = {} }
  while #term_lines > MAX_SCROLLBACK do
    table.remove(term_lines, 1)
  end
end

local function append_run(line, text, fg, bg)
  if not text or text == "" then return end
  fg, bg = fg or FG, bg or BG
  line.text = line.text .. text
  local last = line.runs[#line.runs]
  if last and last.fg == fg and last.bg == bg then
    last.text = last.text .. text
  else
    line.runs[#line.runs + 1] = { text = text, fg = fg, bg = bg }
  end
end

local function clamp_view()
  local maxOffset = math.max(0, #term_lines - h)
  if view_offset < 0 then view_offset = 0 end
  if view_offset > maxOffset then view_offset = maxOffset end
end

local function update_cursor()
  local start = math.max(1, #term_lines - h + 1)
  local line = term_lines[#term_lines]
  cx = unicode.len(line.text) + 1
  cy = #term_lines - start + 1
end

local function render_line(line, y)
  gpu.setBackground(BG)
  gpu.setForeground(FG)
  gpu.fill(1, y, w, 1, " ")
  if not line then return end

  local x = 1
  for _, run in ipairs(line.runs) do
    if x > w then break end
    local text = unicode.sub(run.text, 1, w - x + 1)
    if text ~= "" then
      gpu.setForeground(run.fg or FG)
      gpu.setBackground(run.bg or BG)
      gpu.set(x, y, text)
      x = x + unicode.len(text)
    end
  end
end

local function render_terminal()
  clamp_view()
  local start = math.max(1, #term_lines - h + 1 - view_offset)
  for row = 1, h do
    render_line(term_lines[start + row - 1], row)
  end

  if view_offset > 0 then
    local tag = "[scroll +" .. tostring(view_offset) .. "]"
    gpu.setBackground(BG)
    gpu.setForeground(0x777777)
    gpu.set(math.max(1, w - unicode.len(tag) + 1), 1, tag)
  end

  update_cursor()
end

local function advance_screen_line()
  if cy >= h then
    gpu.copy(1, 2, w, h - 1, 0, -1)
    gpu.setBackground(BG)
    gpu.fill(1, h, w, 1, " ")
    cy = h
  else
    cy = cy + 1
  end
  cx = 1
end

local function redraw_current_line_from(start_x, text, fg, bg)
  local src = term_lines[#term_lines]
  local keep = math.max(0, start_x - 1)
  local dst = { text = "", runs = {} }

  for _, run in ipairs(src.runs) do
    if keep <= 0 then break end
    local take = math.min(keep, unicode.len(run.text))
    if take > 0 then
      append_run(dst, unicode.sub(run.text, 1, take), run.fg, run.bg)
      keep = keep - take
    end
  end

  append_run(dst, text, fg or FG, bg or BG)
  term_lines[#term_lines] = dst

  if view_offset ~= 0 then
    view_offset = 0
    render_terminal()
  else
    render_line(dst, cy)
    update_cursor()
  end
end

local function draw_block_cursor(x, y, ch)
  if x < 1 or x > w or y < 1 or y > h then return end
  gpu.setBackground(FG)
  gpu.setForeground(BG)
  gpu.set(x, y, ch ~= "" and ch or " ")
  gpu.setBackground(BG)
  gpu.setForeground(FG)
end

local function scroll_terminal(direction)
  view_offset = view_offset + (direction or 0) * 3
  clamp_view()
  render_terminal()
end

function api.write(txt)
  txt = tostring(txt or "")
  local fg = gpu.getForeground() or FG
  local bg = gpu.getBackground() or BG

  if view_offset ~= 0 then
    view_offset = 0
    render_terminal()
  end

  local pos = 1
  local len = unicode.len(txt)
  while pos <= len do
    local line = term_lines[#term_lines]
    local used = unicode.len(line.text)
    local free = w - used

    if free <= 0 then
      new_line()
      advance_screen_line()
    else
      local chunk = unicode.sub(txt, pos, pos + free - 1)
      local nl = chunk:find("\n", 1, true)

      if nl then
        chunk = chunk:sub(1, nl - 1)
      end

      if chunk ~= "" then
        append_run(line, chunk, fg, bg)
        gpu.setForeground(fg)
        gpu.setBackground(bg)
        gpu.set(used + 1, cy, chunk)
        used = used + unicode.len(chunk)
        cx = used + 1
        pos = pos + unicode.len(chunk)
      end

      if nl then
        pos = pos + 1
        new_line()
        advance_screen_line()
      elseif used >= w then
        new_line()
        advance_screen_line()
      end
    end
  end

  gpu.setForeground(fg)
  gpu.setBackground(bg)
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
  term_lines = { { text = "", runs = {} } }
  view_offset = 0
  cx, cy = 1, 1
  render_terminal()
end

function api.getCwd()    return cwd end
function api.setCwd(p)   cwd = p end
function api.getCursor() return cx, cy end
function api.setCursor(x, y) cx, cy = x, y end

function api.getUser()
  return auth.getUser(current_user) or { name = current_user, uid = 0, home = "/root" }
end

local function setUserInternal(name)
  local u = auth.getUser(name)
  if not u then return false, "no such user" end
  current_user = name
  cwd = u.home
  return true
end

function api.setUser(name, token)
  if token ~= SESSION_TOKEN then return false, "permission denied" end
  return setUserInternal(name)
end

function api.login(name, password)
  local target = auth.getUser(name)
  if not target then return false, "no such user" end
  if current_user ~= "root" and not auth.verify(name, password or "") then
    return false, "authentication failure"
  end
  return setUserInternal(name)
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

function api.securityContext()
  local u = api.getUser()
  return {
    user = u.name,
    uid = u.uid,
    home = u.home,
    root = (u.uid == 0 or u.name == "root")
  }
end

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
    local display = mask and string.rep("*", unicode.len(buf)) or buf
    redraw_current_line_from(sx, display, FG, BG)
    local curX = sx + unicode.len(display)
    draw_block_cursor(curX, sy, " ")
  end
  redraw()
  while true do
    local sig = {coroutine.yield()}
    if sig[1] == "key_down" then
      local char, code = sig[3], sig[4]
      if code == 28 then
        local display = mask and string.rep("*", unicode.len(buf)) or buf
        redraw_current_line_from(sx, display, FG, BG)
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
    elseif sig[1] == "scroll" then
      scroll_terminal(sig[5] or 0)
      if view_offset == 0 then redraw() end
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
local cmdLoadErrors = {}
local COMMAND_CAPS = {
  passwd = { "fs.system" }
}

local function commandContext(name)
  local ctx = api.securityContext()
  if COMMAND_CAPS[name] then
    ctx.caps = COMMAND_CAPS[name]
  end
  return ctx
end

do
  local files = fs.list("/Libraries/MES")
  if files then
    for _, f in ipairs(files) do
      if f:sub(-4) == ".lua" then
        local path = "/Libraries/MES/" .. f
        local code = fs.readAll(path)
        if code then
          local fn, lerr = load(code, "=" .. path, "bt", _ENV)
          if fn then
            local ok, result = xpcall(fn, function(e)
              return diagnostics.make(e, nil, path)
            end)
            if ok and type(result) == "function" then
              cmds[f:sub(1, -5)] = result
            elseif not ok then
              cmdLoadErrors[#cmdLoadErrors + 1] = result
            end
          else
            cmdLoadErrors[#cmdLoadErrors + 1] = diagnostics.message(lerr, path)
          end
        end
      end
    end
  end
end

local function run_foreground(label, fn, opts)
  local fgToken = nil
  if unit and unit.call then
    fgToken = unit.call("aps", "enterForeground", label, opts or api.securityContext())
  end

  local function finish(ok, err)
    if unit and unit.call then
      unit.call("aps", "leaveForeground", fgToken)
    end
    view_offset = 0
    render_terminal()
    return ok, err
  end

  local co = coroutine.create(fn)
  local ok, err = coroutine.resume(co)
  if not ok then
    return finish(false, diagnostics.make(err, co, label))
  end

  while coroutine.status(co) ~= "dead" do
    local sig = {coroutine.yield()}
    if sig[1] == "atom_interrupt" then
      return finish(false, "interrupted")
    end

    ok, err = coroutine.resume(co, table.unpack(sig))
    if not ok then
      return finish(false, diagnostics.make(err, co, label))
    end
  end

  return finish(true)
end

local function drain_task_errors()
  local count = 0
  while #cmdLoadErrors > 0 do
    count = count + 1
    diagnostics.render(table.remove(cmdLoadErrors, 1), api, {
      title = "Command load failed"
    })
  end
  if not unit or not unit.call then return count end
  while true do
    local item = unit.call("aps", "popError")
    if not item then return count end
    count = count + 1
    diagnostics.render(item, api, {
      title = "Task crashed: " .. tostring(item.name or "unknown")
    })
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
    redraw_current_line_from(sx, buf, FG, BG)
    local cur_x = sx + unicode.len(unicode.sub(buf, 1, pos))
    local ch = unicode.sub(buf, pos + 1, pos + 1)
    if ch == "" then ch = " " end
    draw_block_cursor(cur_x, sy, ch)
  end

  redraw()

  while true do
    local sig = {coroutine.yield()}
    if not sig[1] then
      if drain_task_errors() > 0 then
        promptFn()
        sx, sy = cx, cy
        redraw()
      end
    elseif sig[1] == "key_down" then
      local char, code = sig[3], sig[4]
      if code == 28 then
        redraw_current_line_from(sx, buf, FG, BG)
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
            redraw_current_line_from(sx, buf, FG, BG)
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
    elseif sig[1] == "scroll" then
      scroll_terminal(sig[5] or 0)
      if view_offset == 0 then redraw() end
    end
  end
end

api.clear()
gpu.setForeground(0x00FF00)
api.print("Atom OS v1.0 - MES")
gpu.setForeground(0xFFFFFF)

local function atomUIAutostart()
  local cfg = fs.readAll("/etc/atomui.cfg")
  if not cfg then return false end
  for line in tostring(cfg):gmatch("[^\r\n]+") do
    local key, value = line:match("^([%w_%.%-]+)%s*=%s*(.-)%s*$")
    if key == "autostart" then return value == "true" or value == "1" end
  end
  return false
end

if atomUIAutostart() and cmds.atomui then
  local ok, err = run_foreground("atomui", function()
    cmds.atomui({}, api)
  end, commandContext("atomui"))
  if not ok and err ~= "interrupted" then
    diagnostics.render(err, api, { title = "AtomUI autostart failed" })
  end
end

while true do
  drain_task_errors()
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
      local ok, err = run_foreground(cmd, function()
        cmds[cmd](args, api)
      end, commandContext(cmd))
      if not ok then
        if err == "interrupted" then api.print("^C")
        else diagnostics.render(err, api, { title = "Command crashed: " .. cmd }) end
      end
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
          local fn, lerr = load(code, "=" .. scriptPath, "bt", scriptEnv)
          if fn then
            local ok2, runerr = run_foreground(scriptPath, function()
              fn(args, api)
            end, api.securityContext())
            if not ok2 then
              if runerr == "interrupted" then api.print("^C")
              else diagnostics.render(runerr, api, { title = "Script crashed" }) end
            end
          else
            diagnostics.render(diagnostics.message(lerr, scriptPath), api, { title = "Syntax error" })
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
