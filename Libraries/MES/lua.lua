return function(args, api)
  local gpu = require("graphics")
  local unicode = require("unicode")
  
  api.print("Lua REPL 5.3 (Atom OS)")
  api.print("Type 'exit' to quit.")
  
  local env = setmetatable({}, {__index = _G})

  local function managed_read()
    local buffer = ""
    while true do
      local sig = {coroutine.yield()}
      if sig[1] == "key_down" then
        local char, code = sig[3], sig[4]
        if code == 28 then -- Enter
          api.write("\n")
          return buffer
        elseif code == 14 then -- Backspace
          if #buffer > 0 then
            buffer = unicode.sub(buffer, 1, -2)
            -- Hack: move cursor back, print space, move back again
            -- Since we don't have getCursor, we rely on \8 (backspace char) if supported
            -- OR we just reprint " \b" (space then backspace)
            -- But without low level cursor control it's hard.
            -- Visual feedback: just print a special char for deletion for now
            api.write(" \8 ") -- Try to erase
          end
        elseif char >= 32 then
          local c = unicode.char(char)
          buffer = buffer .. c
          api.write(c)
        end
      end
    end
  end
  
  while true do
    gpu.setForeground(0xFFFF00)
    api.write("lua> ")
    gpu.setForeground(0xFFFFFF)
    
    local code_str = managed_read()
    
    if code_str == "exit" then break end
    
    -- Try to load as expression first (return ...)
    local fn, err = load("return " .. code_str, "=repl", "t", env)
    if not fn then
      -- If failed, try as statement
      fn, err = load(code_str, "=repl", "t", env)
    end
    
    if fn then
      local ok, res = pcall(fn)
      if ok then
        if res ~= nil then api.print(tostring(res)) end
      else
        api.print("Error: " .. tostring(res))
      end
    else
      api.print("Syntax Error: " .. tostring(err))
    end
  end
end