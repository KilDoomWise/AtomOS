return function(args, api)
  local gpu = require("graphics")
  local fs  = require("filesystem")
  local unicode = require("unicode")
  local diagnostics = require("diagnostics")

  local w, _ = gpu.getResolution()

  -- File execution mode: lua <file.lua> [args...]
  if args[1] then
    local path = api.resolve(args[1])
    if not fs.exists(path) then
      api.print("lua: '" .. args[1] .. "': file not found")
      return
    end
    local code = fs.readAll(path)
    if not code then api.print("lua: cannot read '" .. args[1] .. "'"); return end
    local scriptEnv = setmetatable({
      print = function(...) api.print(...) end,
      io    = { write = function(...) for i = 1, select("#", ...) do api.write(tostring(select(i, ...))) end end },
    }, {__index = _ENV})
    local fn, lerr = load(code, "=" .. path, "bt", scriptEnv)
    if not fn then
      diagnostics.render(diagnostics.message(lerr, path), api, { title = "Lua syntax error" })
      return
    end
    local passArgs = {}
    for i = 2, #args do passArgs[#passArgs+1] = args[i] end
    fn(passArgs, api)
    return
  end

  api.print("Lua 5.3 REPL  (Atom OS)  —  type 'exit' to quit")

  local env = setmetatable({}, {__index = _G})
  local read_line  -- forward declaration; defined below
  -- Inject terminal-backed stdlib missing from sandbox
  env.print = function(...)
    local t = {}
    for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end
    api.print(table.concat(t, "\t"))
  end
  env.io = {
    write = function(...) for i = 1, select("#", ...) do api.write(tostring(select(i, ...))) end end,
    read  = function() return read_line("") end,
  }

  -- Line editor using MES cursor tracking
  read_line = function(prompt)
    gpu.setForeground(0xFFFF00)
    api.write(prompt)
    gpu.setForeground(0xFFFFFF)

    local sx, sy = api.getCursor()
    local buf = ""
    local pos = 0

    local function redraw()
      -- Clear from (sx, sy) to end of line
      gpu.setBackground(0x000000)
      gpu.setForeground(0xFFFFFF)
      gpu.fill(sx, sy, w - sx + 1, 1, " ")
      if #buf > 0 then
        gpu.set(sx, sy, unicode.sub(buf, 1, w - sx + 1))
      end
      -- Cursor block
      local curX = sx + unicode.len(unicode.sub(buf, 1, pos))
      local ch = unicode.sub(buf, pos + 1, pos + 1)
      gpu.setBackground(0xFFFFFF)
      gpu.setForeground(0x000000)
      gpu.set(curX, sy, ch ~= "" and ch or " ")
      gpu.setBackground(0x000000)
      gpu.setForeground(0xFFFFFF)
    end

    redraw()

    while true do
      local sig = {coroutine.yield()}
      if sig[1] == "key_down" then
        local char, code = sig[3], sig[4]
        if code == 28 then               -- Enter
          gpu.setBackground(0x000000)
          gpu.fill(sx, sy, w - sx + 1, 1, " ")
          if #buf > 0 then gpu.set(sx, sy, buf) end
          local newX = sx + unicode.len(buf)
          api.setCursor(newX, sy)
          api.write("\n")
          return buf
        elseif code == 14 then           -- Backspace
          if pos > 0 then
            buf = unicode.sub(buf, 1, pos - 1) .. unicode.sub(buf, pos + 1)
            pos = pos - 1
            redraw()
          end
        elseif code == 211 then          -- Delete
          if pos < unicode.len(buf) then
            buf = unicode.sub(buf, 1, pos) .. unicode.sub(buf, pos + 2)
            redraw()
          end
        elseif code == 203 then          -- Left
          if pos > 0 then pos = pos - 1; redraw() end
        elseif code == 205 then          -- Right
          if pos < unicode.len(buf) then pos = pos + 1; redraw() end
        elseif code == 199 then pos = 0; redraw()                   -- Home
        elseif code == 207 then pos = unicode.len(buf); redraw()   -- End
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

  while true do
    local code_str = read_line("lua> ")
    if code_str == "exit" then break end

    -- Strip leading `local` so variables persist across lines in env.
    -- e.g. `local s = 1`  →  `s = 1`  →  stored in env, visible next line.
    local exec_str = code_str:gsub("^(%s*)local%s+", "%1")

    -- Try expression first, then statement
    local fn, err = load("return " .. exec_str, "=repl", "t", env)
    if not fn then
      fn, err = load(exec_str, "=repl", "t", env)
    end
    if fn then
      local ok, result = xpcall(fn, function(e)
        return diagnostics.make(e, nil, "Lua REPL")
      end)
      if ok then
        if result ~= nil then
          gpu.setForeground(0xAAFFAA)
          api.print("=> " .. tostring(result))
          gpu.setForeground(0xFFFFFF)
        end
      else
        diagnostics.render(result, api, { title = "Lua REPL error" })
      end
    else
      diagnostics.render(diagnostics.message(err, "Lua REPL"), api, { title = "Lua REPL syntax" })
    end
  end
end
