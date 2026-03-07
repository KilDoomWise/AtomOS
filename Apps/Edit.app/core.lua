return function(state)
  local core = {}
  local fs = require("filesystem")
  local unicode = require("unicode")

  local COMP_LIST = {
    "local", "function", "return", "if", "then", "else", "elseif", "end",
    "for", "while", "do", "and", "or", "not", "true", "false", "repeat", "until", "break",
    "require", "print", "math", "table", "string", "io", "gpu", "pcall", "xpcall",
    "error", "assert", "pairs", "ipairs", "type", "tostring", "tonumber", "unicode", "coroutine"
  }

  function core.normPath(path)
    if not path or path == "" then return "/" end
    if path:sub(1, 1) ~= "/" then path = "/" .. path end
    local parts = {}
    for p in path:gmatch("[^/]+") do
      if p == ".." then if #parts > 0 then table.remove(parts) end
      elseif p ~= "." then parts[#parts + 1] = p end
    end
    if #parts == 0 then return "/" end
    return "/" .. table.concat(parts, "/")
  end

  function core.pushHistory()
    local snap = {cx = state.cx, cy = state.cy, buffer = {}}
    for i, v in ipairs(state.buffer) do snap.buffer[i] = v end
    table.insert(state.history, snap)
    if #state.history > 15 then table.remove(state.history, 1) end
  end

  function core.undo()
    if #state.history == 0 then return false end
    local snap = table.remove(state.history)
    state.buffer = snap.buffer
    state.cx = snap.cx
    state.cy = snap.cy
    state.modified = true
    state.sel = nil
    state.lastAction = "undo"
    return true
  end

  function core.updateGhost()
    state.ghostText = nil
    if not state.isLua or not state.target then return end
    local line = state.buffer[state.cy] or ""
    local before = unicode.sub(line, 1, state.cx - 1)
    local word = before:match("[%a_][%w_]*$")
    if word and unicode.len(word) >= 2 then
      for _, w in ipairs(COMP_LIST) do
        if w:sub(1, #word) == word and #w > #word then
          state.ghostText = w:sub(#word + 1)
          return
        end
      end
    end
  end

  function core.refreshTree()
    state.visibleNodes = {}
    if not state.workspace then return end
    local function walk(dir, depth)
      local list = fs.list(dir) or {}
      local items = {}
      for _, f in ipairs(list) do table.insert(items, f) end
      table.sort(items, function(a, b)
        local ad = a:sub(-1) == "/"
        local bd = b:sub(-1) == "/"
        if ad == bd then return a:lower() < b:lower() end
        return ad
      end)
      for _, f in ipairs(items) do
        local isDir = f:sub(-1) == "/"
        local name = isDir and f:sub(1, -2) or f
        local fullPath = dir == "/" and ("/" .. name) or (dir .. "/" .. name)
        table.insert(state.visibleNodes, {name = name, path = fullPath, isDir = isDir, depth = depth})
        if isDir and state.expandedDirs[fullPath] then walk(fullPath, depth + 1) end
      end
    end
    local rootName = state.workspace:match("([^/]+)$") or "/"
    table.insert(state.visibleNodes, {name = rootName, path = state.workspace, isDir = true, depth = 0, isRoot = true})
    if state.expandedDirs[state.workspace] then walk(state.workspace, 1) end
  end

  function core.openFile(path)
    if fs.isDir(path) then return false end
    local data = fs.readAll(path)
    state.target = path
    state.isLua = path:match("%.lua$") ~= nil
    state.buffer = {}
    if data then
      data = data:gsub("\r", "")
      for line in (data .. "\n"):gmatch("([^\n]*)\n") do table.insert(state.buffer, line) end
    end
    if #state.buffer == 0 then state.buffer = {""} end
    state.cx, state.cy, state.scrollX, state.scrollY = 1, 1, 0, 0
    state.sel, state.history, state.lastAction = nil, {}, ""
    state.modified = false
    return true
  end

  function core.closeFile()
    state.target = nil
    state.buffer = {""}
    state.cx, state.cy, state.scrollX, state.scrollY = 1, 1, 0, 0
    state.sel, state.history, state.lastAction = nil, {}, ""
    state.modified = false
    state.isLua = false
  end

  function core.init()
    state.expandedDirs = {}
    state.sidebarScroll = 0
    local path = state.args and state.args[1]
    if not path then 
      if state.api then state.api.print("Usage: edit <filename or directory>") end
      state.running = false
      return 
    end
    local targetPath = state.api and state.api.resolve(path) or core.normPath(path)
    if fs.exists(targetPath) and fs.isDir(targetPath) then
      state.workspace = targetPath:gsub("/$", "")
      if state.workspace == "" then state.workspace = "/" end
      state.sidebarW = 26
      state.expandedDirs[state.workspace] = true
      core.refreshTree()
      state.target = nil
      state.buffer = {""}
    else
      state.sidebarW = 0
      core.openFile(targetPath)
    end
  end

  function core.selNorm()
    if not state.sel then return nil end
    local ar, ac, br, bc = state.sel[1], state.sel[2], state.sel[3], state.sel[4]
    if ar > br or (ar == br and ac > bc) then return br, bc, ar, ac end
    return ar, ac, br, bc
  end

  function core.getSelText()
    local r1, c1, r2, c2 = core.selNorm()
    if not r1 then return "" end
    if r1 == r2 then return unicode.sub(state.buffer[r1], c1, c2 - 1) end
    local lines = {unicode.sub(state.buffer[r1], c1)}
    for i = r1 + 1, r2 - 1 do table.insert(lines, state.buffer[i]) end
    table.insert(lines, unicode.sub(state.buffer[r2], 1, c2 - 1))
    return table.concat(lines, "\n")
  end

  function core.selDelete()
    local r1, c1, r2, c2 = core.selNorm()
    if not r1 then return end
    if r1 == r2 then
      state.buffer[r1] = unicode.sub(state.buffer[r1], 1, c1 - 1) .. unicode.sub(state.buffer[r1], c2)
    else
      state.buffer[r1] = unicode.sub(state.buffer[r1], 1, c1 - 1) .. unicode.sub(state.buffer[r2], c2)
      for i = r2, r1 + 1, -1 do table.remove(state.buffer, i) end
    end
    state.cy, state.cx, state.sel = r1, c1, nil
    state.modified = true
  end

  function core.insertTab()
    if state.sel then core.selDelete() end
    state.buffer[state.cy] = unicode.sub(state.buffer[state.cy], 1, state.cx - 1) .. "  " .. unicode.sub(state.buffer[state.cy], state.cx)
    state.cx = state.cx + 2
    state.modified = true
  end

  function core.save()
    if not state.target then return false end
    local f = fs.open(state.target, "w")
    if f then 
      fs.write(f, table.concat(state.buffer, "\n"))
      fs.close(f)
      state.modified = false
      return true
    end
    return false
  end

  return core
end