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
  local SETTINGS_PATH = "/Apps/Edit.app/data/settings.lua"

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

  function core.snapshot()
    local snap = {cx = state.cx, cy = state.cy, buffer = {}}
    for i, v in ipairs(state.buffer) do snap.buffer[i] = v end
    return snap
  end

  function core.restoreSnapshot(snap)
    state.buffer = {}
    for i, v in ipairs(snap.buffer or {}) do state.buffer[i] = v end
    if #state.buffer == 0 then state.buffer = {""} end
    state.cx = snap.cx or 1
    state.cy = snap.cy or 1
    state.sel = nil
    state.modified = true
    core.bumpFindVersion()
  end

  function core.pushHistory()
    local snap = core.snapshot()
    table.insert(state.history, snap)
    state.redoHistory = {}
    if #state.history > 80 then table.remove(state.history, 1) end
  end

  function core.bumpFindVersion(force)
    state.findScrollMarksCache = nil
    if force then
      state.findVersion = (state.findVersion or 0) + 1
    elseif state.findTerm and state.findTerm ~= "" then
      state.sbCache = nil
    end
    if not force then
      state.bufferVersion = (state.bufferVersion or 0) + 1
      state.findCache = nil
      state.stickyContextKey = nil
    end
  end

  function core.setFindTerm(term)
    term = term or ""
    if state.findTerm ~= term then
      state.findTerm = term
      state.findCurrent = nil
      state.findIndex, state.findTotal = 0, 0
      core.bumpFindVersion(true)
    end
  end

  function core.setFindCurrent(match)
    local old = state.findCurrent
    if not old and not match then return end
    if old and match and old.line == match.line and old.start == match.start and old.finish == match.finish then
      return
    end
    state.findCurrent = match
    if state.ui then
      if old then state.ui.invalidateLine(old.line) end
      if match then state.ui.invalidateLine(match.line) end
    end
  end

  function core.clearFind()
    if state.findTerm == "" and not state.findCurrent and (state.findIndex or 0) == 0 then return end
    local old = state.findCurrent
    state.findTerm = ""
    state.findCurrent = nil
    state.findIndex, state.findTotal = 0, 0
    state.findCache = nil
    state.findScrollMarksCache = nil
    core.bumpFindVersion(true)
    if state.ui then
      if old then state.ui.invalidateLine(old.line) end
      state.ui.invalidateEditor()
    end
  end

  function core.findLineMatches(line, term, lineNo)
    local matches = {}
    if not term or term == "" then return matches end
    local from = 1
    local termLen = unicode.len(term)
    while true do
      local byteStart, byteEnd = line:find(term, from, true)
      if not byteStart then break end
      local charStart = unicode.len(line:sub(1, byteStart - 1)) + 1
      matches[#matches + 1] = {
        line = lineNo,
        start = charStart,
        finish = charStart + termLen - 1
      }
      from = byteEnd + 1
    end
    return matches
  end
  

  function core.findMatches(term)
    local version = state.bufferVersion or 0
    if state.findCache and state.findCache.term == term and state.findCache.version == version then
      return state.findCache.matches
    end
    local matches = {}
    if not term or term == "" then return matches end
    for li, line in ipairs(state.buffer) do
      local lineMatches = core.findLineMatches(line, term, li)
      for _, match in ipairs(lineMatches) do matches[#matches + 1] = match end
    end
    state.findCache = {term = term, version = version, matches = matches}
    return matches
  end

  function core.undo()
    if #state.history == 0 then return false end
    table.insert(state.redoHistory, core.snapshot())
    if #state.redoHistory > 80 then table.remove(state.redoHistory, 1) end
    local snap = table.remove(state.history)
    state.lastAction = "undo"
    core.restoreSnapshot(snap)
    return true
  end

  function core.redo()
    if #state.redoHistory == 0 then return false end
    table.insert(state.history, core.snapshot())
    if #state.history > 80 then table.remove(state.history, 1) end
    local snap = table.remove(state.redoHistory)
    state.lastAction = "redo"
    core.restoreSnapshot(snap)
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

  function core.loadSettings()
    local data = fs.readAll(SETTINGS_PATH)
    if not data then return end
    local chunk = load(data, "=edit-settings", "t", {})
    if not chunk then return end
    local ok, cfg = pcall(chunk)
    if not ok or type(cfg) ~= "table" then return end
    local keys = {"showSticky", "showGuides", "showFindHighlight", "showSyntax", "showScrollMarks"}
    for _, key in ipairs(keys) do
      if type(cfg[key]) == "boolean" then state[key] = cfg[key] end
    end
  end

  function core.saveSettings()
    fs.makeDir("/Apps/Edit.app/data")
    local f = fs.open(SETTINGS_PATH, "w")
    if not f then return false end
    fs.write(f, "return {\n")
    fs.write(f, "  showSticky = " .. tostring(state.showSticky ~= false) .. ",\n")
    fs.write(f, "  showGuides = " .. tostring(state.showGuides ~= false) .. ",\n")
    fs.write(f, "  showFindHighlight = " .. tostring(state.showFindHighlight ~= false) .. ",\n")
    fs.write(f, "  showSyntax = " .. tostring(state.showSyntax ~= false) .. ",\n")
    fs.write(f, "  showScrollMarks = " .. tostring(state.showScrollMarks ~= false) .. ",\n")
    fs.write(f, "}\n")
    fs.close(f)
    return true
  end

  function core.captureCurrentFile()
    if not state.target then return end
    state.fileStates[state.target] = {
      buffer = state.buffer, cx = state.cx, cy = state.cy,
      scrollX = state.scrollX, scrollY = state.scrollY,
      modified = state.modified, history = state.history,
      redoHistory = state.redoHistory, lastAction = state.lastAction,
      isLua = state.isLua
    }
  end

  function core.isDirty(path)
    if state.target == path then return state.modified end
    local fileState = state.fileStates and state.fileStates[path]
    return fileState and fileState.modified or false
  end

  function core.displayPath(path)
    if state.workspace and path:sub(1, #state.workspace) == state.workspace then
      local s = path:sub(#state.workspace + 1)
      if s:sub(1, 1) == "/" then s = s:sub(2) end
      return s ~= "" and s or path
    end
    return path
  end

  function core.quickFiles()
    if state.quickFileCache then return state.quickFileCache end
    local files = {}
    local root = state.workspace or "/"
    local function walk(dir)
      local list = fs.list(dir) or {}
      local items = {}
      for _, f in ipairs(list) do items[#items + 1] = f end
      table.sort(items, function(a, b) return a:lower() < b:lower() end)
      for _, f in ipairs(items) do
        local isDir = f:sub(-1) == "/"
        local name = isDir and f:sub(1, -2) or f
        local fullPath = dir == "/" and ("/" .. name) or (dir .. "/" .. name)
        if isDir then
          if #files < 600 then walk(fullPath) end
        else
          files[#files + 1] = fullPath
          if #files >= 600 then return end
        end
      end
    end
    walk(root)
    state.quickFileCache = files
    return files
  end

  function core.quickMatches(term)
    term = (term or ""):lower()
    local result = {}
    for _, path in ipairs(core.quickFiles()) do
      local shown = core.displayPath(path)
      if term == "" or shown:lower():find(term, 1, true) then
        result[#result + 1] = {path = path, text = shown}
        if #result >= 8 then break end
      end
    end
    return result
  end

  function core.refreshTree()
    state.visibleNodes = {}
    state.quickFileCache = nil
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
    if state.target == path then return true end
    core.captureCurrentFile()
    local cached = state.fileStates[path]
    if cached then
      state.target = path
      state.isLua = cached.isLua
      state.buffer = cached.buffer or {""}
      state.cx, state.cy = cached.cx or 1, cached.cy or 1
      state.scrollX, state.scrollY = cached.scrollX or 0, cached.scrollY or 0
      state.sel = nil
      state.history, state.redoHistory = cached.history or {}, cached.redoHistory or {}
      state.lastAction = cached.lastAction or ""
      state.modified = cached.modified or false
      state.findCurrent = nil
      state.findIndex, state.findTotal = 0, 0
      state.bufferVersion = (state.bufferVersion or 0) + 1
      state.findCache = nil
      state.stickyContextKey = nil
      core.bumpFindVersion(true)
      return true
    end
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
    state.sel, state.history, state.redoHistory, state.lastAction = nil, {}, {}, ""
    state.findCurrent = nil
    state.findIndex, state.findTotal = 0, 0
    state.bufferVersion = (state.bufferVersion or 0) + 1
    state.findCache = nil
    state.stickyContextKey = nil
    core.bumpFindVersion(true)
    state.modified = false
    return true
  end

  function core.closeFile()
    core.captureCurrentFile()
    state.target = nil
    state.buffer = {""}
    state.cx, state.cy, state.scrollX, state.scrollY = 1, 1, 0, 0
    state.sel, state.history, state.redoHistory, state.lastAction = nil, {}, {}, ""
    state.findCurrent = nil
    state.findIndex, state.findTotal = 0, 0
    state.bufferVersion = (state.bufferVersion or 0) + 1
    state.findCache = nil
    state.stickyContextKey = nil
    core.bumpFindVersion(true)
    state.modified = false
    state.isLua = false
  end

  function core.init()
    core.loadSettings()
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

  function core.selectAll()
    local lastLine = #state.buffer
    local lastCol = unicode.len(state.buffer[lastLine] or "") + 1
    state.sel = {1, 1, lastLine, lastCol}
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
    core.bumpFindVersion()
  end

  function core.insertText(text)
    if not text or text == "" then return false end
    if state.sel then core.selDelete() end
    text = text:gsub("\r", "")
    local lines = {}
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do table.insert(lines, line) end
    if #lines == 1 then
      state.buffer[state.cy] = unicode.sub(state.buffer[state.cy], 1, state.cx - 1) .. lines[1] .. unicode.sub(state.buffer[state.cy], state.cx)
      state.cx = state.cx + unicode.len(lines[1])
    else
      local after = unicode.sub(state.buffer[state.cy], state.cx)
      state.buffer[state.cy] = unicode.sub(state.buffer[state.cy], 1, state.cx - 1) .. lines[1]
      for i = 2, #lines - 1 do table.insert(state.buffer, state.cy + i - 1, lines[i]) end
      table.insert(state.buffer, state.cy + #lines - 1, lines[#lines] .. after)
      state.cy = state.cy + #lines - 1
      state.cx = unicode.len(lines[#lines]) + 1
    end
    state.modified = true
    core.bumpFindVersion()
    return true
  end

  function core.cutCurrentLine()
    local removed = state.buffer[state.cy] or ""
    if #state.buffer == 1 then
      state.buffer[1] = ""
      state.cx, state.cy = 1, 1
    else
      table.remove(state.buffer, state.cy)
      if state.cy > #state.buffer then state.cy = #state.buffer end
      state.cx = math.min(state.cx, unicode.len(state.buffer[state.cy]) + 1)
    end
    state.sel = nil
    state.modified = true
    core.bumpFindVersion()
    return removed .. "\n"
  end

  function core.insertTab()
    if state.sel then core.selDelete() end
    state.buffer[state.cy] = unicode.sub(state.buffer[state.cy], 1, state.cx - 1) .. "  " .. unicode.sub(state.buffer[state.cy], state.cx)
    state.cx = state.cx + 2
    state.modified = true
    core.bumpFindVersion()
  end

  function core.save()
    if not state.target then return false end
    local f = fs.open(state.target, "w")
    if f then 
      fs.write(f, table.concat(state.buffer, "\n"))
      fs.close(f)
      state.modified = false
      if state.fileStates[state.target] then state.fileStates[state.target].modified = false end
      return true
    end
    return false
  end

  return core
end
