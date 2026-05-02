return function(state)
  local fs = require("filesystem")
  local sys = require("io")
  local proc = require("process")
  local unicode = require("unicode")

  local okLauncher, launcher = pcall(require, "applauncher")
  local okNode, atomNode = pcall(require, "atomui_node")

  local screen = state.screen
  local C = state.theme.color
  local L = state.theme.layout
  local S = state.theme.symbol
  local ui = state.widgets

  local windows = {
    list = {},
    seq = 0,
    dragging = nil,
    lastSystemTick = -1
  }

  local TITLES = {
    about = "О системе",
    apps = "Приложения",
    files = "Файлы",
    system = "Система",
    textedit = "TextEdit",
    calculator = "Калькулятор",
    taskmgr = "Диспетчер",
    settings = "Настройки",
    terminal = "Терминал"
  }

  local openTextPath

  local function bounds(win)
    return {x = win.x, y = win.y, w = win.w + 2, h = win.h + 1}
  end

  local function intersectsClip(r)
    local c = screen.clip
    if not c then return true end
    return not (r.x + r.w - 1 < c.x or r.y + r.h - 1 < c.y or
                r.x > c.x + c.w - 1 or r.y > c.y + c.h - 1)
  end

  local function rect(x, y, w, h)
    return {x = x, y = y, w = w, h = h}
  end

  local function invalidateTaskbar()
    if state.desktop then
      state.desktop.invalidate(1, state.h - L.taskbarH + 1, state.w, L.taskbarH)
    end
  end

  local function invalidateWin(win)
    if win.minimized then
      invalidateTaskbar()
      return
    end
    if state.desktop then
      local b = bounds(win)
      state.desktop.invalidate(b.x, b.y, b.w, b.h)
    end
  end

  local function clampCoords(x, y, win)
    local minY = 2
    local maxY = math.max(minY, state.h - L.taskbarH - win.h)
    local maxX = math.max(1, state.w - win.w - 1)
    return math.max(1, math.min(maxX, x)),
           math.max(minY, math.min(maxY, y))
  end

  local function clamp(win)
    win.x, win.y = clampCoords(win.x, win.y, win)
  end

  local function invalidateRect(r)
    if state.desktop and r and r.w > 0 and r.h > 0 then
      state.desktop.invalidate(r.x, r.y, r.w, r.h)
    end
  end

  local function overlap(a, b)
    local x1 = math.max(a.x, b.x)
    local y1 = math.max(a.y, b.y)
    local x2 = math.min(a.x + a.w - 1, b.x + b.w - 1)
    local y2 = math.min(a.y + a.h - 1, b.y + b.h - 1)
    if x2 < x1 or y2 < y1 then return nil end
    return rect(x1, y1, x2 - x1 + 1, y2 - y1 + 1)
  end

  local function invalidateExposed(old, new)
    local o = overlap(old, new)
    if not o then
      invalidateRect(old)
      return
    end

    invalidateRect(rect(old.x, old.y, old.w, o.y - old.y))
    invalidateRect(rect(old.x, o.y + o.h, old.w, old.y + old.h - (o.y + o.h)))
    invalidateRect(rect(old.x, o.y, o.x - old.x, o.h))
    invalidateRect(rect(o.x + o.w, o.y, old.x + old.w - (o.x + o.w), o.h))
  end

  local function center(w, h)
    return math.max(1, math.floor((state.w - w) / 2)),
           math.max(2, math.floor((state.h - L.taskbarH - h) / 2))
  end

  function windows.bring(win)
    for i, w in ipairs(windows.list) do
      if w == win then table.remove(windows.list, i); break end
    end
    win.minimized = false
    windows.list[#windows.list + 1] = win
    invalidateWin(win)
    invalidateTaskbar()
  end

  function windows.close(win)
    invalidateWin(win)
    for i, w in ipairs(windows.list) do
      if w == win then
        table.remove(windows.list, i)
        invalidateTaskbar()
        return true
      end
    end
    return false
  end

  function windows.open(kind, opts)
    for _, win in ipairs(windows.list) do
      if win.kind == kind then
        win.minimized = false
        if kind == "textedit" and opts and opts.path and openTextPath then
          openTextPath(win, opts.path)
        end
        windows.bring(win)
        return win
      end
    end

    opts = opts or {}
    local ww = opts.w or (kind == "about" and 64 or kind == "system" and 70 or kind == "textedit" and 78 or kind == "calculator" and 42 or kind == "taskmgr" and 74 or kind == "settings" and 76 or kind == "terminal" and 84 or 72)
    local wh = opts.h or (kind == "about" and 20 or kind == "system" and 22 or kind == "textedit" and 26 or kind == "calculator" and 19 or kind == "taskmgr" and 24 or kind == "settings" and 25 or kind == "terminal" and 27 or 24)
    ww = math.max(L.winMinW, math.min(state.w - 4, ww))
    wh = math.max(L.winMinH, math.min(state.h - L.taskbarH - 3, wh))
    local x, y = center(ww, wh)

    windows.seq = windows.seq + 1
    local win = {
      id = windows.seq,
      kind = kind,
      title = opts.title or TITLES[kind] or kind,
      x = opts.x or x,
      y = opts.y or y,
      w = ww,
      h = wh,
      scroll = 0,
      selected = 1,
      cwd = "/",
      apps = nil,
      files = nil,
      lines = {""},
      cx = 1,
      cy = 1,
      textScroll = 0,
      filePath = opts.path or "/home/note.txt",
      pathEdit = false,
      calcExpr = "",
      calcResult = "",
      taskSelected = 1,
      settingsTab = 1,
      settingsConfig = nil,
      dirty = false,
      status = "",
      termLines = nil,
      termInput = "",
      termHistory = {},
      termHist = 1,
      termScroll = 0,
      termCwd = nil,
      termMode = "shell",
      termLuaEnv = nil,
      termCommands = nil,
      minimized = false
    }
    clamp(win)
    windows.list[#windows.list + 1] = win
    if kind == "textedit" and opts.path and openTextPath then
      openTextPath(win, opts.path)
    end
    invalidateWin(win)
    return win
  end

  function windows.reflow()
    for _, win in ipairs(windows.list) do
      win.w = math.max(L.winMinW, math.min(state.w - 4, win.w))
      win.h = math.max(L.winMinH, math.min(state.h - L.taskbarH - 3, win.h))
      clamp(win)
    end
    if state.desktop then state.desktop.invalidateAll() end
  end

  function windows.minimize(win)
    if win.minimized then return end
    if windows.dragging and windows.dragging.win == win then
      windows.dragging = nil
    end
    invalidateWin(win)
    win.minimized = true
    invalidateTaskbar()
  end

  function windows.restore(win)
    win.minimized = false
    windows.bring(win)
  end

  local function topVisible()
    for i = #windows.list, 1, -1 do
      if not windows.list[i].minimized then return windows.list[i] end
    end
    return nil
  end

  function windows.isTop(win)
    return topVisible() == win
  end

  local function contentRect(win)
    return win.x + 1, win.y + 2, win.w - 2, win.h - 3
  end

  local function drawFrame(win, active)
    local x, y, w, h = win.x, win.y, win.w, win.h
    local titleBg = active and C.active or C.accent

    screen.fill(x + 2, y + 1, w, h, " ", C.text, C.shadow)
    screen.fill(x, y, w, h, " ", C.text, C.window)
    screen.fill(x, y, w, 1, " ", C.text, titleBg)
    screen.text(x + 2, y, ui.cut(win.title, w - 12), C.text, titleBg)
    screen.text(x + w - 8, y, " " .. S.min .. " ", C.text, titleBg)
    screen.text(x + w - 4, y, " " .. S.close .. " ", C.text, titleBg)
    screen.fill(x, y + h - 1, w, 1, "─", C.divider, C.window)
  end

  local function memText(v)
    if not v then return "?" end
    return string.format("%dK", math.floor(v / 1024))
  end

  local function pctText(value, max)
    if not max or max <= 0 then return "0%" end
    return string.format("%d%%", math.floor((value or 0) / max * 100 + 0.5))
  end

  local function drawAbout(win)
    local x, y, w, h = contentRect(win)
    screen.fill(x, y, w, h, " ", C.text, C.window)

    local total = sys.totalMemory() or 0
    local free = sys.freeMemory() or 0
    local used = math.max(0, total - free)
    local energy = sys.energy() or 0
    local maxEnergy = sys.maxEnergy() or 0
    local uptime = sys.uptime() or 0
    local components = sys.componentCount() or 0
    local timeText = "?"
    if sys.date and sys.time then
      local okTime, t = pcall(sys.time)
      if okTime and t then
        local okDate, text = pcall(sys.date, "%H:%M", t)
        if okDate and text then timeText = text end
      end
    end

    screen.text(x + 2, y + 1, "AtomOS 1.0", C.text, C.window)
    screen.text(x + 2, y + 3, "AtomUI.app", C.subtext, C.window)
    screen.textRight(x + w - 3, y + 1, timeText, C.subtext, C.window)

    screen.fill(x + 2, y + 6, w - 4, 1, " ", C.text, C.panel)
    screen.text(x + 4, y + 6, "Память  " .. memText(used) .. " / " .. memText(total), C.subtext, C.panel)
    ui.thinBar(x + 27, y + 6, math.max(10, w - 38), used, total, C.info, C.panel)
    screen.textRight(x + w - 4, y + 6, pctText(used, total), C.text, C.panel)

    screen.fill(x + 2, y + 8, w - 4, 1, " ", C.text, C.panel)
    screen.text(x + 4, y + 8, "Энергия", C.subtext, C.panel)
    ui.thinBar(x + 27, y + 8, math.max(10, w - 38), energy, maxEnergy, C.ok, C.panel)
    screen.textRight(x + w - 4, y + 8, pctText(energy, maxEnergy), C.text, C.panel)

    screen.text(x + 2, y + 11, "Компоненты: " .. tostring(components), C.text, C.window)
    screen.text(x + 2, y + 13, string.format("Uptime: %02d:%02d:%02d", math.floor(uptime / 3600), math.floor(uptime / 60) % 60, math.floor(uptime) % 60), C.subtext, C.window)
    screen.text(x + 2, y + h - 2, "Интерфейсный квадрат: 2 ширина × 1 высота.", C.muted, C.window)
  end

  local function drawSystem(win)
    local x, y, w, h = contentRect(win)
    screen.fill(x, y, w, h, " ", C.text, C.window)

    local total = sys.totalMemory() or 0
    local free = sys.freeMemory() or 0
    local used = math.max(0, total - free)
    local energy = sys.energy() or 0
    local maxEnergy = sys.maxEnergy() or 0
    local uptime = sys.uptime() or 0

    screen.text(x + 1, y, "Система", C.text, C.window)
    screen.textRight(x + w - 2, y, string.format("uptime %02d:%02d", math.floor(uptime / 3600), math.floor(uptime / 60) % 60), C.subtext, C.window)

    screen.text(x + 1, y + 3, "Память  " .. memText(used) .. " / " .. memText(total), C.subtext, C.window)
    ui.thinBar(x + 15, y + 3, math.max(10, w - 24), used, total, C.info, C.window)
    screen.textRight(x + w - 2, y + 3, pctText(used, total), C.text, C.window)

    screen.text(x + 1, y + 5, "Энергия", C.subtext, C.window)
    ui.thinBar(x + 15, y + 5, math.max(10, w - 24), energy, maxEnergy, C.ok, C.window)
    screen.textRight(x + w - 2, y + 5, pctText(energy, maxEnergy), C.text, C.window)

    local tasks = proc.list() or {}
    screen.text(x + 1, y + 8, "Процессы", C.text, C.window)
    local maxRows = math.max(0, h - 10)
    for i = 1, math.min(#tasks, maxRows) do
      local t = tasks[i]
      local row = y + 9 + i
      local bg = (i % 2 == 0) and C.window2 or C.panel
      screen.fill(x + 1, row, w - 2, 1, " ", C.text, bg)
      local name = ui.cut(t.name or "?", 24)
      local user = ui.cut(t.user or "?", 10)
      screen.text(x + 2, row, string.format("%2d", t.id or i), C.muted, bg)
      screen.text(x + 6, row, user, t.root and C.warn or C.subtext, bg)
      screen.text(x + 18, row, name, C.text, bg)
      screen.textRight(x + w - 3, row, tostring(t.status or ""), C.muted, bg)
    end
  end

  local function trimSlash(path)
    path = tostring(path or "")
    while #path > 1 and path:sub(-1) == "/" do path = path:sub(1, -2) end
    return path
  end

  local function refreshApps(win)
    local out = {}
    for _, entry in ipairs(fs.list("/Apps") or {}) do
      local clean = trimSlash(entry)
      if clean:match("%.app$") then out[#out + 1] = clean end
    end
    table.sort(out)
    win.apps = out
    if win.selected > #out then win.selected = math.max(1, #out) end
  end

  local function readAtomApp(package)
    local path = "/Apps/" .. tostring(package or "") .. "/atomapp.lua"
    local code = fs.readAll(path)
    if not code then return nil end
    local chunk = load(code, "=" .. path, "bt", _ENV)
    if not chunk then return nil end
    local ok, meta = pcall(chunk)
    if ok and type(meta) == "table" then return meta end
    return nil
  end

  local function launchApp(win)
    refreshApps(win)
    local name = win.apps[win.selected]
    if not name then return end
    if name == "AtomUI.app" then
      if state.desktop then state.desktop.toast("AtomUI уже запущен", "warn") end
      return
    end

    local meta = readAtomApp(name)
    if meta and meta.native and meta.kind then
      windows.open(meta.kind, {package = name})
      return
    end

    local path = "/Apps/" .. name
    if okLauncher and launcher and state.api then
      if state.desktop then
        state.desktop.toast("Запуск " .. name, "ok")
        state.desktop.renderDirty()
        screen.flush()
      end
      local ctx = state.api.securityContext and state.api.securityContext() or nil
      local ok, err = launcher.run(path, {}, state.api, _ENV, ctx)
      if state.desktop then state.desktop.invalidateAll() end
      if not ok and state.desktop then
        state.desktop.toast("Не удалось запустить " .. name .. ": " .. tostring(err), "danger")
      end
      return
    end

    local ok, err = proc.spawn(path)
    if state.desktop then
      state.desktop.toast(ok and ("Запущено " .. name) or ("Ошибка запуска: " .. tostring(err)), ok and "ok" or "danger")
    end
  end

  local function drawApps(win)
    refreshApps(win)
    local x, y, w, h = contentRect(win)
    screen.fill(x, y, w, h, " ", C.text, C.window)
    screen.text(x + 1, y, "Пакеты /Apps", C.text, C.window)
    screen.textRight(x + w - 2, y, tostring(#win.apps) .. " app", C.subtext, C.window)

    local rows = h - 5
    for i = 1, math.min(#win.apps, rows) do
      local row = y + 2 + i - 1
      local selected = i == win.selected
      local bg = selected and C.active or ((i % 2 == 0) and C.window2 or C.panel)
      screen.fill(x + 1, row, w - 2, 1, " ", C.text, bg)
      screen.text(x + 3, row, S.app .. " " .. ui.cut(win.apps[i], w - 8), C.text, bg)
    end

    ui.button3(x + 1, y + h - 3, 18, "Запустить", false, S.logo)
    screen.text(x + 22, y + h - 2, "legacy-приложения открываются полноэкранно", C.muted, C.window)
  end

  local function parentPath(path)
    path = trimSlash(path)
    if path == "/" then return "/" end
    local p = path:match("^(.*)/[^/]+$")
    if not p or p == "" then return "/" end
    return p
  end

  local function joinPath(a, b)
    a = trimSlash(a)
    if a == "/" then return "/" .. b end
    return a .. "/" .. b
  end

  local function refreshFiles(win)
    local out = {}
    if win.cwd ~= "/" then out[#out + 1] = {name = "..", path = parentPath(win.cwd), dir = true} end
    for _, entry in ipairs(fs.list(win.cwd) or {}) do
      local clean = trimSlash(entry)
      local path = joinPath(win.cwd, clean)
      out[#out + 1] = {name = clean, path = path, dir = fs.isDir(path)}
    end
    table.sort(out, function(a, b)
      if a.name == ".." then return true end
      if b.name == ".." then return false end
      if a.dir ~= b.dir then return a.dir end
      return a.name:lower() < b.name:lower()
    end)
    win.files = out
    if win.selected > #out then win.selected = math.max(1, #out) end
  end

  local function drawFiles(win)
    refreshFiles(win)
    local x, y, w, h = contentRect(win)
    screen.fill(x, y, w, h, " ", C.text, C.window)
    screen.text(x + 1, y, ui.cut(win.cwd, w - 2), C.text, C.window)
    ui.divider(x + 1, y + 1, w - 2, C.window)

    local rows = h - 3
    for i = 1, math.min(#win.files, rows) do
      local item = win.files[i]
      local row = y + 2 + i - 1
      local selected = i == win.selected
      local bg = selected and C.active or ((i % 2 == 0) and C.window2 or C.panel)
      screen.fill(x + 1, row, w - 2, 1, " ", C.text, bg)
      local icon = item.dir and S.folder or S.file
      screen.text(x + 3, row, icon .. " " .. ui.cut(item.name, w - 8), item.dir and C.info or C.text, bg)
    end
  end

  local function textArea(win)
    local x, y, w, h = contentRect(win)
    return x + 1, y + 2, w - 2, math.max(1, h - 3)
  end

  local function clampText(win, keepView)
    if #win.lines == 0 then win.lines = {""} end
    win.cy = math.max(1, math.min(#win.lines, win.cy or 1))
    local len = unicode.len(win.lines[win.cy] or "")
    win.cx = math.max(1, math.min(len + 1, win.cx or 1))

    local _, _, _, ah = textArea(win)
    local maxScroll = math.max(0, #win.lines - ah)
    win.textScroll = math.max(0, math.min(maxScroll, win.textScroll or 0))

    if not keepView then
      if win.cy - 1 < win.textScroll then win.textScroll = win.cy - 1 end
      if win.cy > win.textScroll + ah then win.textScroll = win.cy - ah end
      win.textScroll = math.max(0, math.min(maxScroll, win.textScroll or 0))
    end
  end

  local function splitLines(data)
    data = tostring(data or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    local lines = {}
    for line in (data .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
    if #lines == 0 then lines = {""} end
    return lines
  end

  openTextPath = function(win, path)
    path = tostring(path or win.filePath or "/home/note.txt")
    if path == "" then path = "/home/note.txt" end
    win.filePath = path
    local data = fs.readAll(path)
    if data then
      win.lines = splitLines(data)
      win.status = "Открыто: " .. path
    else
      win.lines = {""}
      win.status = "Новый файл: " .. path
    end
    win.cx, win.cy, win.textScroll = 1, 1, 0
    win.pathEdit = false
    win.dirty = false
    clampText(win)
    invalidateWin(win)
  end

  local function saveText(win)
    if not fs.exists("/home") then fs.makeDir("/home") end
    local ok, err = fs.writeAll(win.filePath or "/home/note.txt", table.concat(win.lines, "\n"))
    if ok then
      win.dirty = false
      win.status = "Сохранено"
      if state.desktop then state.desktop.toast("TextEdit: сохранено", "ok") end
    else
      win.status = tostring(err or "ошибка сохранения")
      if state.desktop then state.desktop.toast("TextEdit: " .. win.status, "danger") end
    end
    invalidateWin(win)
  end

  local function drawTextEdit(win)
    clampText(win, true)
    local x, y, w, h = contentRect(win)
    screen.fill(x, y, w, h, " ", C.text, C.window)
    screen.fill(x, y, w, 1, " ", C.text, C.panel)
    ui.button1(x + 1, y, 8, "Save", false, S.check)
    ui.button1(x + 10, y, 7, "Open", win.pathEdit, S.folder)
    ui.button1(x + 18, y, 7, "New", false, "+")
    local pathBg = win.pathEdit and C.active or C.field
    screen.fill(x + 26, y, math.max(8, w - 28), 1, " ", C.text, pathBg)
    screen.text(x + 27, y, ui.cut((win.filePath or "/home/note.txt") .. (win.dirty and " *" or ""), math.max(4, w - 31)), win.pathEdit and C.text or C.subtext, pathBg)
    ui.divider(x, y + 1, w, C.window)

    local ax, ay, aw, ah = textArea(win)
    local gutter = 5
    local textW = math.max(1, aw - 1)
    screen.fill(ax, ay, aw, ah, " ", C.text, C.field)
    for row = 1, ah do
      local lineNo = win.textScroll + row
      local sy = ay + row - 1
      local active = lineNo == win.cy
      local bg = active and C.panel or C.field
      screen.fill(ax, sy, textW, 1, " ", C.text, bg)
      if lineNo <= #win.lines then
        screen.textRight(ax + gutter - 2, sy, tostring(lineNo), C.muted, bg)
        screen.text(ax + gutter - 1, sy, "│", C.divider, bg)
        screen.text(ax + gutter + 1, sy, ui.cut(win.lines[lineNo], textW - gutter - 2), C.text, bg)
      end
    end

    local barX = ax + aw - 1
    screen.fill(barX, ay, 1, ah, "│", C.divider, C.field)
    if #win.lines > ah then
      local maxScroll = math.max(1, #win.lines - ah)
      local thumbH = math.max(1, math.floor(ah * ah / #win.lines))
      local thumbY = ay + math.floor((ah - thumbH) * ((win.textScroll or 0) / maxScroll) + 0.5)
      screen.fill(barX, thumbY, 1, thumbH, "█", C.info, C.field)
    else
      screen.set(barX, ay, "█", C.muted, C.field)
    end

    if windows.isTop(win) then
      local cursorY = ay + (win.cy - win.textScroll) - 1
      if cursorY >= ay and cursorY < ay + ah then
        local cursorX = ax + gutter + math.min(win.cx, math.max(1, textW - gutter - 2))
        screen.set(cursorX, cursorY, "▌", C.info, C.panel)
      end
    end

    screen.fill(x, y + h - 1, w, 1, " ", C.subtext, C.panel)
    screen.text(x + 2, y + h - 1, string.format("Ln %d/%d  Col %d", win.cy, #win.lines, win.cx), C.subtext, C.panel)
    if win.status and win.status ~= "" then
      screen.textRight(x + w - 2, y + h - 1, ui.cut(win.status, 24), C.muted, C.panel)
    end
  end

  local function newText(win)
    win.lines = {""}
    win.cx, win.cy, win.textScroll = 1, 1, 0
    win.dirty = false
    win.status = "Новый документ"
    invalidateWin(win)
  end

  local function insertText(win, text)
    local line = win.lines[win.cy] or ""
    win.lines[win.cy] = unicode.sub(line, 1, win.cx - 1) .. text .. unicode.sub(line, win.cx)
    win.cx = win.cx + unicode.len(text)
    win.dirty = true
  end

  local function handleTextKey(win, sig)
    local char, code = sig[3] or 0, sig[4] or 0
    local line = win.lines[win.cy] or ""

    if win.pathEdit then
      if code == 28 then openTextPath(win, win.filePath); return true
      elseif code == 1 then win.pathEdit = false; invalidateWin(win); return true
      elseif code == 14 then
        local len = unicode.len(win.filePath or "")
        if len > 0 then win.filePath = unicode.sub(win.filePath, 1, len - 1) end
      elseif char >= 32 then
        win.filePath = tostring(win.filePath or "") .. unicode.char(char)
      else
        return false
      end
      invalidateWin(win)
      return true
    end

    if char == 19 then saveText(win); return true
    elseif char == 15 then win.pathEdit = true; invalidateWin(win); return true
    elseif code == 200 then win.cy = math.max(1, win.cy - 1)
    elseif code == 208 then win.cy = math.min(#win.lines, win.cy + 1)
    elseif code == 203 then
      if win.cx > 1 then win.cx = win.cx - 1
      elseif win.cy > 1 then
        win.cy = win.cy - 1
        win.cx = unicode.len(win.lines[win.cy] or "") + 1
      end
    elseif code == 205 then
      if win.cx <= unicode.len(line) then win.cx = win.cx + 1
      elseif win.cy < #win.lines then win.cy = win.cy + 1; win.cx = 1 end
    elseif code == 199 then win.cx = 1
    elseif code == 207 then win.cx = unicode.len(line) + 1
    elseif code == 201 then
      local _, _, _, ah = textArea(win)
      win.cy = math.max(1, win.cy - ah)
    elseif code == 209 then
      local _, _, _, ah = textArea(win)
      win.cy = math.min(#win.lines, win.cy + ah)
    elseif code == 14 then
      if win.cx > 1 then
        win.lines[win.cy] = unicode.sub(line, 1, win.cx - 2) .. unicode.sub(line, win.cx)
        win.cx = win.cx - 1
        win.dirty = true
      elseif win.cy > 1 then
        local prev = win.lines[win.cy - 1]
        local prevLen = unicode.len(prev)
        win.lines[win.cy - 1] = prev .. line
        table.remove(win.lines, win.cy)
        win.cy, win.cx = win.cy - 1, prevLen + 1
        win.dirty = true
      end
    elseif code == 211 then
      if win.cx <= unicode.len(line) then
        win.lines[win.cy] = unicode.sub(line, 1, win.cx - 1) .. unicode.sub(line, win.cx + 1)
        win.dirty = true
      elseif win.cy < #win.lines then
        win.lines[win.cy] = line .. win.lines[win.cy + 1]
        table.remove(win.lines, win.cy + 1)
        win.dirty = true
      end
    elseif code == 28 then
      local before = unicode.sub(line, 1, win.cx - 1)
      local after = unicode.sub(line, win.cx)
      win.lines[win.cy] = before
      table.insert(win.lines, win.cy + 1, after)
      win.cy, win.cx = win.cy + 1, 1
      win.dirty = true
    elseif code == 15 then
      insertText(win, "  ")
    elseif char >= 32 then
      insertText(win, unicode.char(char))
    else
      return false
    end

    win.status = ""
    clampText(win)
    invalidateWin(win)
    return true
  end

  local function termRows(win)
    local _, _, _, h = contentRect(win)
    return math.max(1, h - 1)
  end

  local function termWidth(win)
    local _, _, w = contentRect(win)
    return math.max(8, w - 3)
  end

  local function terminalUser()
    if state.api and state.api.getUser then
      local ok, user = pcall(state.api.getUser)
      if ok and user then return user end
    end
    return {name = "atom", uid = 1000, home = "/home"}
  end

  local function terminalHome()
    if state.api and state.api.getHome then
      local ok, home = pcall(state.api.getHome)
      if ok and home and home ~= "" then return home end
    end
    local user = terminalUser()
    return user.home or "/home"
  end

  local function terminalResolve(win, path)
    path = tostring(path or "")
    if path == "" then return win.termCwd or "/" end
    local abs = path:sub(1, 1) == "/" and path or (trimSlash(win.termCwd or "/") .. "/" .. path)
    local parts = {}
    for part in abs:gmatch("[^/]+") do
      if part == ".." then
        if #parts > 0 then table.remove(parts) end
      elseif part ~= "." and part ~= "" then
        parts[#parts + 1] = part
      end
    end
    if #parts == 0 then return "/" end
    return "/" .. table.concat(parts, "/")
  end

  local function terminalPrompt(win)
    local user = terminalUser()
    local sym = ((user.uid == 0) or user.name == "root") and "#" or "$"
    if win.termMode == "lua" then return "lua> " end
    return (win.termCwd or "/") .. " " .. sym .. " "
  end

  local function terminalClamp(win)
    local maxScroll = math.max(0, #(win.termLines or {""}) - termRows(win))
    win.termScroll = math.max(0, math.min(maxScroll, win.termScroll or 0))
  end

  local function terminalBottom(win)
    win.termScroll = math.max(0, #(win.termLines or {""}) - termRows(win))
  end

  local function terminalTrim(win)
    while #(win.termLines or {}) > 300 do
      table.remove(win.termLines, 1)
    end
  end

  local terminalWrite

  local function terminalNewLine(win)
    win.termLines[#win.termLines + 1] = ""
    terminalTrim(win)
  end

  terminalWrite = function(win, text)
    if not win.termLines then win.termLines = {""} end
    text = tostring(text or "")
    if text == "" then return end

    local width = termWidth(win)
    for i = 1, unicode.len(text) do
      local ch = unicode.sub(text, i, i)
      if ch == "\n" then
        terminalNewLine(win)
      else
        local line = win.termLines[#win.termLines] or ""
        if unicode.len(line) >= width then
          terminalNewLine(win)
          line = ""
        end
        win.termLines[#win.termLines] = line .. ch
      end
    end
    terminalBottom(win)
  end

  local function ensureTerminal(win)
    if win.termLines then return end
    win.termLines = {""}
    if not win.termCwd and state.api and state.api.getCwd then
      local okCwd, cwd = pcall(state.api.getCwd)
      if okCwd and cwd and cwd ~= "" then win.termCwd = cwd end
    end
    if not win.termCwd or win.termCwd == "" then win.termCwd = terminalHome() end
    win.termInput = ""
    win.termHistory = {}
    win.termHist = 1
    win.termScroll = 0
    win.termMode = "shell"
    terminalWrite(win, "AtomOS Terminal · MES\n")
    terminalWrite(win, "help - команды, lua - встроенный REPL, edit <file> - открыть TextEdit\n")
  end

  local function splitArgs(line)
    local out, buf, quote = {}, "", nil
    for i = 1, unicode.len(line) do
      local ch = unicode.sub(line, i, i)
      if quote then
        if ch == quote then quote = nil else buf = buf .. ch end
      elseif ch == "\"" or ch == "'" then
        quote = ch
      elseif ch:match("%s") then
        if buf ~= "" then out[#out + 1], buf = buf, "" end
      else
        buf = buf .. ch
      end
    end
    if buf ~= "" then out[#out + 1] = buf end
    return out
  end

  local function terminalCommandNames()
    local out = {help = true, clear = true, cd = true, pwd = true, edit = true, open = true, apps = true, htop = true, taskmgr = true, lua = true, exit = true}
    for _, entry in ipairs(fs.list("/Libraries/MES") or {}) do
      local name = tostring(entry):match("^(.-)%.lua$")
      if name then out[name] = true end
    end
    local list = {}
    for name in pairs(out) do list[#list + 1] = name end
    table.sort(list)
    return list
  end

  local function terminalPrintColumns(win, list)
    if #list == 0 then return end
    local colW = 0
    for _, item in ipairs(list) do colW = math.max(colW, unicode.len(item)) end
    colW = colW + 2
    local cols = math.max(1, math.floor(termWidth(win) / colW))
    for i, item in ipairs(list) do
      terminalWrite(win, string.format("%-" .. colW .. "s", item))
      if i % cols == 0 then terminalWrite(win, "\n") end
    end
    if #list % cols ~= 0 then terminalWrite(win, "\n") end
  end

  local function terminalComplete(win)
    local input = tostring(win.termInput or "")
    local before, word = input:match("^(.*%s)(%S*)$")
    if not before then before, word = "", input end
    local first = before == ""
    local matches = {}

    if first and not word:find("/", 1, true) then
      for _, name in ipairs(terminalCommandNames()) do
        if name:sub(1, #word):lower() == word:lower() then matches[#matches + 1] = name end
      end
    else
      local dirPart = word:match("^(.*[/])") or ""
      local namePart = word:sub(#dirPart + 1)
      local searchDir = dirPart ~= "" and terminalResolve(win, dirPart) or (win.termCwd or "/")
      for _, entry in ipairs(fs.list(searchDir) or {}) do
        local clean = trimSlash(entry)
        if clean:sub(1, #namePart):lower() == namePart:lower() then
          local full = joinPath(searchDir, clean)
          matches[#matches + 1] = dirPart .. clean .. (fs.isDir(full) and "/" or "")
        end
      end
      table.sort(matches)
    end

    if #matches == 1 then
      win.termInput = before .. matches[1]
    elseif #matches > 1 then
      terminalWrite(win, "\n")
      terminalPrintColumns(win, matches)
    end
  end

  local function terminalApi(win)
    local api = {}
    function api.write(text) terminalWrite(win, text) end
    function api.print(...)
      local t = {}
      for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end
      terminalWrite(win, table.concat(t, "\t") .. "\n")
    end
    function api.clear() win.termLines = {""}; win.termScroll = 0 end
    function api.getCwd() return win.termCwd or "/" end
    function api.setCwd(path) win.termCwd = terminalResolve(win, path) end
    function api.getHome() return terminalHome() end
    function api.getHostname()
      if state.api and state.api.getHostname then
        local ok, name = pcall(state.api.getHostname)
        if ok and name then return name end
      end
      return "atom"
    end
    function api.setHostname(name)
      if state.api and state.api.setHostname then
        return state.api.setHostname(name)
      end
      return false, "hostname api unavailable"
    end
    function api.getUser() return terminalUser() end
    function api.isRoot()
      local user = terminalUser()
      return user.uid == 0 or user.name == "root"
    end
    function api.securityContext()
      if state.api and state.api.securityContext then
        local ok, ctx = pcall(state.api.securityContext)
        if ok and ctx then return ctx end
      end
      local user = terminalUser()
      return {user = user.name, uid = user.uid, home = user.home, root = (user.uid == 0 or user.name == "root")}
    end
    function api.resolve(path) return terminalResolve(win, path) end
    function api.login(name, password)
      if state.api and state.api.login then
        return state.api.login(name, password)
      end
      return false, "login api unavailable"
    end
    function api.setUser(name, token)
      if state.api and state.api.setUser then
        return state.api.setUser(name, token)
      end
      return false, "login api unavailable"
    end
    function api.getCursor() return 1, #(win.termLines or {""}) end
    function api.setCursor() end
    function api.readLine(prompt)
      if prompt then terminalWrite(win, prompt) end
      terminalWrite(win, "\n")
      return ""
    end
    function api.readPassword(prompt) return api.readLine(prompt) end
    return api
  end

  local function terminalFakeGpu(win)
    local gpu = {fg = C.text, bg = C.field}
    function gpu.setForeground(value) local old = gpu.fg; gpu.fg = value or old; return old end
    function gpu.setBackground(value) local old = gpu.bg; gpu.bg = value or old; return old end
    function gpu.getForeground() return gpu.fg end
    function gpu.getBackground() return gpu.bg end
    function gpu.getResolution() return termWidth(win), termRows(win) end
    function gpu.maxResolution() return state.maxW or state.w, state.maxH or state.h end
    function gpu.getDepth() return 4 end
    function gpu.fill() end
    function gpu.copy() end
    function gpu.set(_, y, text)
      terminalWrite(win, tostring(text or ""))
      if y and y > 1 then terminalWrite(win, "\n") end
    end
    return gpu
  end

  local function terminalDiagnostics()
    local diagnostics = {}
    function diagnostics.message(err, label) return {error = tostring(err), label = label} end
    function diagnostics.make(err, _, label) return {error = tostring(err), label = label} end
    function diagnostics.render(item, api, opts)
      local title = opts and opts.title or item.label or "error"
      api.print(title .. ": " .. tostring(item.error or item.traceback or item))
    end
    return diagnostics
  end

  local function terminalLoadCommand(win, name)
    win.termCommands = win.termCommands or {}
    if win.termCommands[name] ~= nil then
      return win.termCommands[name] ~= false and win.termCommands[name] or nil
    end

    local path = "/Libraries/MES/" .. tostring(name) .. ".lua"
    local code = fs.readAll(path)
    if not code then win.termCommands[name] = false; return nil end

    local fakeGpu = terminalFakeGpu(win)
    local fakeDiagnostics = terminalDiagnostics()
    local env = setmetatable({
      require = function(lib)
        if lib == "graphics" then return fakeGpu end
        if lib == "diagnostics" then return fakeDiagnostics end
        return require(lib)
      end,
      print = function(...) terminalApi(win).print(...) end
    }, {__index = _ENV})
    env._G = env

    local chunk, loadErr = load(code, "=" .. path, "bt", env)
    if not chunk then
      terminalWrite(win, name .. ": " .. tostring(loadErr) .. "\n")
      win.termCommands[name] = false
      return nil
    end
    local ok, fn = pcall(chunk)
    if ok and type(fn) == "function" then
      win.termCommands[name] = fn
      return fn
    end
    terminalWrite(win, name .. ": bad command\n")
    win.termCommands[name] = false
    return nil
  end

  local function terminalLuaEnv(win)
    if win.termLuaEnv then return win.termLuaEnv end
    local env = setmetatable({}, {__index = _ENV})
    env.print = function(...)
      local t = {}
      for i = 1, select("#", ...) do t[i] = tostring(select(i, ...)) end
      terminalWrite(win, table.concat(t, "\t") .. "\n")
    end
    env.io = {
      write = function(...)
        for i = 1, select("#", ...) do terminalWrite(win, tostring(select(i, ...))) end
      end
    }
    win.termLuaEnv = env
    return env
  end

  local function terminalRunLuaLine(win, line)
    if line == "exit" or line == ".exit" then
      win.termMode = "shell"
      terminalWrite(win, "leave lua\n")
      return
    end

    local env = terminalLuaEnv(win)
    local exec = tostring(line or ""):gsub("^(%s*)local%s+", "%1")
    local fn, err = load("return " .. exec, "=AtomUI lua", "t", env)
    if not fn then fn, err = load(exec, "=AtomUI lua", "t", env) end
    if not fn then terminalWrite(win, tostring(err) .. "\n"); return end

    local ok, result = xpcall(fn, function(e)
      return debug and debug.traceback and debug.traceback(e, 2) or tostring(e)
    end)
    if ok then
      if result ~= nil then terminalWrite(win, "=> " .. tostring(result) .. "\n") end
    else
      local msg = tostring(result):match("([^\n]+)") or tostring(result)
      terminalWrite(win, msg .. "\n")
    end
  end

  local function terminalRunLuaFile(win, args)
    local spec = args[1]
    if not spec then
      win.termMode = "lua"
      terminalWrite(win, "Lua REPL внутри AtomUI, exit чтобы выйти\n")
      return
    end

    local path = terminalResolve(win, spec)
    if not fs.exists(path) then terminalWrite(win, "lua: file not found: " .. spec .. "\n"); return end
    if fs.isDir(path) then terminalWrite(win, "lua: is a directory: " .. spec .. "\n"); return end
    local code = fs.readAll(path)
    if not code then terminalWrite(win, "lua: cannot read: " .. spec .. "\n"); return end

    local env = terminalLuaEnv(win)
    local fn, err = load(code, "=" .. path, "bt", env)
    if not fn then terminalWrite(win, tostring(err) .. "\n"); return end

    local pass = {}
    for i = 2, #args do pass[#pass + 1] = args[i] end
    local ok, result = xpcall(function() return fn(pass, terminalApi(win)) end, function(e)
      return debug and debug.traceback and debug.traceback(e, 2) or tostring(e)
    end)
    if not ok then
      local msg = tostring(result):match("([^\n]+)") or tostring(result)
      terminalWrite(win, msg .. "\n")
    end
  end

  local function terminalOpenTarget(win, spec)
    local target = terminalResolve(win, spec or win.termCwd or "/")
    if fs.isDir(target) then
      if target:match("%.app$") then
        local package = target:match("[^/]+$")
        local meta = readAtomApp(package)
        if meta and meta.native and meta.kind then
          windows.open(meta.kind, {package = package})
          terminalWrite(win, "opened " .. package .. "\n")
        else
          terminalWrite(win, "legacy app: use MES full screen for " .. target .. "\n")
        end
      else
        local fwin = windows.open("files")
        fwin.cwd = target
        invalidateWin(fwin)
        terminalWrite(win, "files: " .. target .. "\n")
      end
    elseif fs.exists(target) then
      windows.open("textedit", {path = target})
      terminalWrite(win, "TextEdit: " .. target .. "\n")
    else
      terminalWrite(win, "open: not found: " .. tostring(spec) .. "\n")
    end
  end

  local function terminalHelp(win)
    terminalWrite(win, "AtomUI terminal: MES-команды из /Libraries/MES плюс встроенные:\n")
    terminalPrintColumns(win, {"help", "clear", "cd", "pwd", "edit", "open", "apps", "htop", "taskmgr", "lua", "exit"})
  end

  local function terminalRun(win, line)
    ensureTerminal(win)
    line = tostring(line or "")
    terminalWrite(win, terminalPrompt(win) .. line .. "\n")
    if line == "" then return end

    if win.termMode == "lua" then
      terminalRunLuaLine(win, line)
      return
    end

    local args = splitArgs(line)
    local cmd = table.remove(args, 1)
    if not cmd then return end

    if cmd == "help" then terminalHelp(win); return end
    if cmd == "clear" then win.termLines = {""}; win.termScroll = 0; return end
    if cmd == "pwd" then terminalWrite(win, (win.termCwd or "/") .. "\n"); return end
    if cmd == "cd" then
      local target = args[1] and terminalResolve(win, args[1]) or terminalHome()
      if fs.isDir(target) then win.termCwd = target else terminalWrite(win, "cd: not a directory: " .. tostring(args[1] or target) .. "\n") end
      return
    end
    if cmd == "edit" then windows.open("textedit", {path = terminalResolve(win, args[1] or "/home/note.txt")}); return end
    if cmd == "open" then terminalOpenTarget(win, args[1]); return end
    if cmd == "apps" then windows.open("apps"); return end
    if cmd == "taskmgr" or cmd == "htop" then windows.open("taskmgr"); return end
    if cmd == "atomui" then terminalWrite(win, "AtomUI уже запущен\n"); return end
    if cmd == "exit" then windows.minimize(win); return end
    if cmd == "lua" then terminalRunLuaFile(win, args); return end
    if cmd == "su" or cmd == "passwd" or cmd == "useradd" then
      terminalWrite(win, cmd .. ": ввод паролей пока безопаснее запускать в полноэкранном MES\n")
      return
    end

    local fn = terminalLoadCommand(win, cmd)
    if not fn then terminalWrite(win, cmd .. ": command not found\n"); return end

    local api = terminalApi(win)
    local co = coroutine.create(function() return fn(args, api) end)
    local ok, err = coroutine.resume(co)
    if not ok then
      local msg = tostring(err):match("([^\n]+)") or tostring(err)
      terminalWrite(win, msg .. "\n")
    elseif coroutine.status(co) ~= "dead" then
      terminalWrite(win, cmd .. ": интерактивный полноэкранный режим здесь не поддержан\n")
    end
  end

  local function drawTerminal(win)
    ensureTerminal(win)
    terminalClamp(win)
    local x, y, w, h = contentRect(win)
    screen.fill(x, y, w, h, " ", C.text, C.field)

    local rows = termRows(win)
    local textW = math.max(1, w - 3)
    for row = 1, rows do
      local lineNo = (win.termScroll or 0) + row
      local sy = y + row - 1
      screen.fill(x, sy, w, 1, " ", C.text, C.field)
      local line = win.termLines[lineNo]
      if line then screen.text(x + 1, sy, ui.cut(line, textW), C.text, C.field) end
    end

    local barX = x + w - 1
    screen.fill(barX, y, 1, rows, "│", C.divider, C.field)
    if #win.termLines > rows then
      local maxScroll = math.max(1, #win.termLines - rows)
      local thumbH = math.max(1, math.floor(rows * rows / #win.termLines))
      local thumbY = y + math.floor((rows - thumbH) * ((win.termScroll or 0) / maxScroll) + 0.5)
      screen.fill(barX, thumbY, 1, thumbH, "█", C.info, C.field)
    else
      screen.set(barX, y, "█", C.muted, C.field)
    end

    local prompt = terminalPrompt(win)
    local input = tostring(win.termInput or "")
    local full = prompt .. input
    local maxPrompt = math.max(1, w - 3)
    if unicode.len(full) > maxPrompt then
      full = "…" .. unicode.sub(full, unicode.len(full) - maxPrompt + 2)
    end
    screen.fill(x, y + h - 1, w, 1, " ", C.text, C.panel)
    screen.text(x + 1, y + h - 1, ui.cut(full, maxPrompt), C.text, C.panel)
    if windows.isTop(win) then
      local cx = math.min(x + w - 2, x + unicode.len(full) + 1)
      screen.set(cx, y + h - 1, "▌", C.info, C.panel)
    end
  end

  local function handleTerminalKey(win, sig)
    ensureTerminal(win)
    local char, code = sig[3] or 0, sig[4] or 0

    if char == 3 then
      win.termMode = "shell"
      win.termInput = ""
      terminalWrite(win, "^C\n")
    elseif code == 28 then
      local line = tostring(win.termInput or "")
      if line ~= "" then
        win.termHistory[#win.termHistory + 1] = line
        if #win.termHistory > 100 then table.remove(win.termHistory, 1) end
      end
      win.termHist = #win.termHistory + 1
      win.termInput = ""
      terminalRun(win, line)
    elseif code == 14 then
      local len = unicode.len(win.termInput or "")
      if len > 0 then win.termInput = unicode.sub(win.termInput, 1, len - 1) end
    elseif code == 15 then
      terminalComplete(win)
    elseif code == 200 then
      if #win.termHistory > 0 then
        win.termHist = math.max(1, (win.termHist or (#win.termHistory + 1)) - 1)
        win.termInput = win.termHistory[win.termHist] or ""
      end
    elseif code == 208 then
      if #win.termHistory > 0 then
        win.termHist = math.min(#win.termHistory + 1, (win.termHist or #win.termHistory) + 1)
        win.termInput = win.termHistory[win.termHist] or ""
      end
    elseif code == 201 then
      win.termScroll = math.max(0, (win.termScroll or 0) - termRows(win))
    elseif code == 209 then
      win.termScroll = math.min(math.max(0, #win.termLines - termRows(win)), (win.termScroll or 0) + termRows(win))
    elseif char >= 32 then
      win.termInput = tostring(win.termInput or "") .. unicode.char(char)
      terminalBottom(win)
    else
      return false
    end

    invalidateWin(win)
    return true
  end

  local calcButtons = {
    {"7", "8", "9", "/"},
    {"4", "5", "6", "*"},
    {"1", "2", "3", "-"},
    {"0", ".", "⌫", "+"},
    {"(", ")", "C", "="}
  }

  local function evalCalc(expr)
    expr = tostring(expr or "")
    if expr == "" then return "" end
    if not expr:match("^[%d%+%-%*%/%(%)%.%s]+$") then return "bad expr" end
    local fn, err = load("return " .. expr, "=calculator", "t", {})
    if not fn then return tostring(err or "syntax") end
    local ok, res = pcall(fn)
    if not ok then return tostring(res) end
    return tostring(res)
  end

  local function calcPress(win, key)
    if key == "C" then
      win.calcExpr, win.calcResult = "", ""
    elseif key == "⌫" then
      local len = unicode.len(win.calcExpr or "")
      if len > 0 then win.calcExpr = unicode.sub(win.calcExpr, 1, len - 1) end
    elseif key == "=" then
      win.calcResult = evalCalc(win.calcExpr)
    else
      win.calcExpr = tostring(win.calcExpr or "") .. key
    end
    invalidateWin(win)
  end

  local function drawCalculator(win)
    local x, y, w, h = contentRect(win)
    screen.fill(x, y, w, h, " ", C.text, C.window)
    screen.fill(x + 1, y + 1, w - 2, 3, " ", C.text, C.field)
    screen.text(x + 3, y + 1, ui.cut(win.calcExpr ~= "" and win.calcExpr or "0", w - 6), C.text, C.field)
    screen.textRight(x + w - 3, y + 3, ui.cut(win.calcResult or "", w - 6), C.info, C.field)

    local bw, bh = math.floor((w - 6) / 4), 2
    local by = y + 5
    for row, line in ipairs(calcButtons) do
      for col, label in ipairs(line) do
        local bx = x + 2 + (col - 1) * (bw + 1)
        local active = label == "="
        ui.button1(bx, by + (row - 1) * bh, bw, label, active, "")
      end
    end
  end

  local function handleCalculatorTouch(win, x, y)
    local cx, cy, cw = contentRect(win)
    local bw, bh = math.floor((cw - 6) / 4), 2
    local by = cy + 5
    for row, line in ipairs(calcButtons) do
      for col, label in ipairs(line) do
        local bx = cx + 2 + (col - 1) * (bw + 1)
        local yy = by + (row - 1) * bh
        if x >= bx and x < bx + bw and y == yy then
          calcPress(win, label)
          return true
        end
      end
    end
    return true
  end

  local function handleCalculatorKey(win, sig)
    local char, code = sig[3] or 0, sig[4] or 0
    if code == 28 then calcPress(win, "=")
    elseif code == 14 then calcPress(win, "⌫")
    elseif char == 99 or char == 67 then calcPress(win, "C")
    elseif char >= 32 then
      local ch = unicode.char(char)
      if ch:match("[%d%+%-%*%/%(%)%.]") then calcPress(win, ch) else return false end
    else
      return false
    end
    return true
  end

  local function drawTaskMgr(win)
    local x, y, w, h = contentRect(win)
    screen.fill(x, y, w, h, " ", C.text, C.window)
    local tasks = proc.list() or {}
    if win.taskSelected > #tasks then win.taskSelected = math.max(1, #tasks) end

    screen.fill(x, y, w, 1, " ", C.text, C.panel)
    screen.text(x + 1, y, "PID USER       ROOT  STATUS      NAME", C.subtext, C.panel)
    ui.button1(x + w - 11, y, 9, "Kill", false, "×")

    local rows = h - 3
    for i = 1, math.min(#tasks, rows) do
      local t = tasks[i]
      local row = y + 2 + i - 1
      local selected = i == win.taskSelected
      local bg = selected and C.active or ((i % 2 == 0) and C.window2 or C.panel)
      screen.fill(x + 1, row, w - 2, 1, " ", C.text, bg)
      screen.text(x + 2, row, string.format("%3d", t.id or i), C.muted, bg)
      screen.text(x + 7, row, ui.cut(t.user or "?", 10), C.subtext, bg)
      screen.text(x + 19, row, t.root and "yes" or "no ", t.root and C.warn or C.muted, bg)
      screen.text(x + 25, row, ui.cut(t.status or "", 10), C.muted, bg)
      screen.text(x + 37, row, ui.cut(t.name or "?", w - 40), C.text, bg)
    end
    screen.text(x + 1, y + h - 1, tostring(#tasks) .. " процессов", C.muted, C.window)
  end

  local function killSelectedTask(win)
    local tasks = proc.list() or {}
    local t = tasks[win.taskSelected]
    if not t then return end
    local ok, err = proc.kill(t.id)
    if state.desktop then
      state.desktop.toast(ok and ("Завершён PID " .. tostring(t.id)) or ("Kill: " .. tostring(err)), ok and "ok" or "danger")
    end
    invalidateWin(win)
  end

  local function handleTaskMgrTouch(win, x, y)
    local cx, cy, cw, ch = contentRect(win)
    if y == cy and x >= cx + cw - 11 and x < cx + cw - 2 then killSelectedTask(win); return true end
    local row = y - (cy + 2) + 1
    if row >= 1 and row <= ch - 3 then
      win.taskSelected = row
      invalidateWin(win)
    end
    return true
  end

  local function handleTaskMgrKey(win, sig)
    local code = sig[4] or 0
    if code == 200 then win.taskSelected = math.max(1, win.taskSelected - 1)
    elseif code == 208 then win.taskSelected = win.taskSelected + 1
    elseif code == 28 or code == 211 then killSelectedTask(win)
    else return false end
    invalidateWin(win)
    return true
  end

  local settingsTabs = {
    {label = "Основное", id = "general"},
    {label = "Экран", id = "display"},
    {label = "Запуск", id = "startup"},
    {label = "Драйверы", id = "drivers"}
  }

  local function parseAtomConfig()
    local cfg = {}
    local data = fs.readAll("/etc/atomui.cfg")
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

  local function writeAtomConfig(cfg)
    if not fs.exists("/etc") then fs.makeDir("/etc") end
    local keys, out = {}, {}
    for k in pairs(cfg or {}) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do
      local v = cfg[k]
      if type(v) == "boolean" then v = v and "true" or "false" end
      out[#out + 1] = k .. "=" .. tostring(v)
    end
    return fs.writeAll("/etc/atomui.cfg", table.concat(out, "\n") .. "\n")
  end

  local function loadSettings(win)
    if win.settingsConfig then return win.settingsConfig end
    local cfg = nil
    if okNode and atomNode and atomNode.getConfig then
      local ok, result = pcall(atomNode.getConfig)
      if ok and type(result) == "table" then cfg = result end
    end
    cfg = cfg or parseAtomConfig()
    if cfg.autostart == nil then cfg.autostart = false end
    cfg.width = tonumber(cfg.width) or state.w
    cfg.height = tonumber(cfg.height) or state.h
    win.settingsConfig = cfg
    return cfg
  end

  local function saveSettings(win, patch)
    local cfg = loadSettings(win)
    for k, v in pairs(patch or {}) do cfg[k] = v end
    win.settingsConfig = cfg
    local ok, err = false, "atomui_node_unavailable"
    if okNode and atomNode and atomNode.setConfig then
      local callOk, res, callErr = pcall(atomNode.setConfig, cfg)
      ok, err = callOk and res, callErr
    end
    if not ok then ok, err = writeAtomConfig(cfg) end
    win.status = ok and "Сохранено" or tostring(err or "ошибка")
    invalidateWin(win)
    return ok
  end

  local function resolutionOptions()
    local maxW, maxH = state.maxW or state.w, state.maxH or state.h
    local base = {
      {80, 25},
      {100, 30},
      {120, 40},
      {160, 50},
      {maxW, maxH}
    }
    local out, seen = {}, {}
    for _, r in ipairs(base) do
      local w, h = math.min(r[1], maxW), math.min(r[2], maxH)
      local key = w .. "x" .. h
      if w >= 60 and h >= 20 and not seen[key] then
        seen[key] = true
        out[#out + 1] = {w, h}
      end
    end
    return out
  end

  local function drawSettings(win)
    local x, y, w, h = contentRect(win)
    local cfg = loadSettings(win)
    screen.fill(x, y, w, h, " ", C.text, C.window)
    local sideW = 16
    screen.fill(x, y, sideW, h, " ", C.text, C.panel)
    for i, tab in ipairs(settingsTabs) do
      local bg = (win.settingsTab == i) and C.active or C.panel
      screen.fill(x + 1, y + 1 + (i - 1) * 2, sideW - 2, 1, " ", C.text, bg)
      screen.text(x + 2, y + 1 + (i - 1) * 2, ui.cut(tab.label, sideW - 4), C.text, bg)
    end

    local cx = x + sideW + 2
    local cw = w - sideW - 3
    local tab = settingsTabs[win.settingsTab].id
    screen.text(cx, y + 1, settingsTabs[win.settingsTab].label, C.text, C.window)
    ui.divider(cx, y + 2, cw, C.window)

    if tab == "general" then
      screen.text(cx, y + 4, "AtomUI Node", C.subtext, C.window)
      screen.text(cx + 14, y + 4, okNode and "online" or "offline", okNode and C.ok or C.danger, C.window)
      screen.text(cx, y + 6, "Разрешение", C.subtext, C.window)
      screen.text(cx + 14, y + 6, tostring(state.w) .. "×" .. tostring(state.h), C.text, C.window)
      screen.text(cx, y + 8, "Конфиг", C.subtext, C.window)
      screen.text(cx + 14, y + 8, "/etc/atomui.cfg", C.text, C.window)
    elseif tab == "display" then
      screen.text(cx, y + 4, "Выбор разрешения", C.subtext, C.window)
      for i, r in ipairs(resolutionOptions()) do
        local row = y + 6 + i - 1
        local selected = tonumber(cfg.width) == r[1] and tonumber(cfg.height) == r[2]
        screen.fill(cx, row, cw, 1, " ", C.text, selected and C.active or C.window)
        screen.text(cx + 2, row, (selected and "✓ " or "  ") .. tostring(r[1]) .. "×" .. tostring(r[2]), C.text, selected and C.active or C.window)
      end
    elseif tab == "startup" then
      ui.checkbox(cx, y + 4, "Запускать AtomUI при старте MES", cfg.autostart and true or false, true, C.window)
      screen.text(cx, y + 7, "MES прочитает /etc/atomui.cfg при следующей загрузке.", C.muted, C.window)
    elseif tab == "drivers" then
      local drivers = {}
      if okNode and atomNode and atomNode.listDrivers then
        local ok, result = pcall(atomNode.listDrivers)
        if ok and type(result) == "table" then drivers = result end
      end
      screen.text(cx, y + 4, ui.cut("Драйверы объявляются через unit.call('atomui','announce', ...)", cw), C.muted, C.window)
      if #drivers == 0 then
        screen.text(cx, y + 7, "Активных объявлений пока нет.", C.subtext, C.window)
      else
        for i = 1, math.min(#drivers, h - 8) do
          screen.text(cx, y + 6 + i, ui.cut(drivers[i].name, cw - 2), C.text, C.window)
        end
      end
    end

    if win.status and win.status ~= "" then
      screen.textRight(x + w - 2, y + h - 1, ui.cut(win.status, 28), C.muted, C.window)
    end
  end

  local function handleSettingsTouch(win, x, y)
    local cx, cy, cw, ch = contentRect(win)
    local sideW = 16
    if x >= cx and x < cx + sideW then
      local idx = math.floor((y - cy - 1) / 2) + 1
      if idx >= 1 and idx <= #settingsTabs then
        win.settingsTab = idx
        win.status = ""
        invalidateWin(win)
      end
      return true
    end

    local cfg = loadSettings(win)
    local bodyX = cx + sideW + 2
    local tab = settingsTabs[win.settingsTab].id
    if tab == "startup" and y == cy + 4 and x >= bodyX and x < bodyX + 36 then
      saveSettings(win, {autostart = not cfg.autostart})
      return true
    elseif tab == "display" then
      local row = y - (cy + 6) + 1
      local opts = resolutionOptions()
      local r = opts[row]
      if r then
        saveSettings(win, {width = r[1], height = r[2]})
        if state.applyResolution then state.applyResolution(r[1], r[2]) end
        return true
      end
    end
    return true
  end

  local function renderContent(win)
    if win.kind == "about" then drawAbout(win)
    elseif win.kind == "system" then drawSystem(win)
    elseif win.kind == "apps" then drawApps(win)
    elseif win.kind == "files" then drawFiles(win)
    elseif win.kind == "textedit" then drawTextEdit(win)
    elseif win.kind == "calculator" then drawCalculator(win)
    elseif win.kind == "taskmgr" then drawTaskMgr(win)
    elseif win.kind == "settings" then drawSettings(win)
    elseif win.kind == "terminal" then drawTerminal(win)
    end
  end

  function windows.renderAll()
    local active = topVisible()
    for i, win in ipairs(windows.list) do
      if not win.minimized and intersectsClip(bounds(win)) then
        drawFrame(win, win == active)
        renderContent(win)
      end
    end
  end

  local function hitWindow(x, y)
    for i = #windows.list, 1, -1 do
      local win = windows.list[i]
      if not win.minimized and x >= win.x and x < win.x + win.w and y >= win.y and y < win.y + win.h then
        if y == win.y and x >= win.x + win.w - 4 then return win, "close" end
        if y == win.y and x >= win.x + win.w - 8 then return win, "min" end
        if y == win.y then return win, "title" end
        return win, "content"
      end
    end
    return nil
  end

  local function handleContent(win, x, y)
    local cx, cy, cw, ch = contentRect(win)
    if x < cx or y < cy or x >= cx + cw or y >= cy + ch then return true end

    if win.kind == "apps" then
      local launchY = cy + ch - 3
      if y >= launchY and y <= launchY + 2 and x >= cx + 1 and x < cx + 19 then
        launchApp(win)
        return true
      end
      local row = y - (cy + 2) + 1
      refreshApps(win)
      if row >= 1 and row <= #win.apps then
        win.selected = row
        invalidateWin(win)
      end
    elseif win.kind == "files" then
      local row = y - (cy + 2) + 1
      refreshFiles(win)
      local item = win.files[row]
      if item then
        win.selected = row
        if item.dir then
          win.cwd = item.path
          win.selected = 1
        else
          windows.open("textedit", {path = item.path})
          if state.desktop then state.desktop.toast("Открыто в TextEdit: " .. item.name, "ok") end
        end
        invalidateWin(win)
      end
    elseif win.kind == "textedit" then
      if y == cy then
        if x >= cx + 1 and x < cx + 9 then saveText(win); return true end
        if x >= cx + 10 and x < cx + 17 then openTextPath(win, win.filePath); return true end
        if x >= cx + 18 and x < cx + 25 then newText(win); return true end
        if x >= cx + 26 and x < cx + cw - 1 then win.pathEdit = true; invalidateWin(win); return true end
      end

      local ax, ay, aw, ah = textArea(win)
      if y >= ay and y < ay + ah then
        local lineNo = win.textScroll + (y - ay) + 1
        if lineNo >= 1 and lineNo <= #win.lines then
          local gutter = 5
          win.cy = lineNo
          win.cx = math.max(1, math.min(unicode.len(win.lines[win.cy]) + 1, x - (ax + gutter)))
          clampText(win)
          invalidateWin(win)
        end
      end
    elseif win.kind == "calculator" then
      return handleCalculatorTouch(win, x, y)
    elseif win.kind == "taskmgr" then
      return handleTaskMgrTouch(win, x, y)
    elseif win.kind == "settings" then
      return handleSettingsTouch(win, x, y)
    elseif win.kind == "terminal" then
      ensureTerminal(win)
      invalidateWin(win)
      return true
    end
    return true
  end

  function windows.handle(sig)
    local ev = sig[1]
    if ev == "key_down" then
      local win = topVisible()
      if win and win.kind == "textedit" then return handleTextKey(win, sig) end
      if win and win.kind == "calculator" then return handleCalculatorKey(win, sig) end
      if win and win.kind == "taskmgr" then return handleTaskMgrKey(win, sig) end
      if win and win.kind == "terminal" then return handleTerminalKey(win, sig) end
      return false
    elseif ev == "drag" and windows.dragging then
      local x, y = sig[3], sig[4]
      local drag = windows.dragging
      local nx, ny = clampCoords(x - drag.dx, y - drag.dy, drag.win)
      local dx, dy = nx - drag.win.x, ny - drag.win.y
      if dx ~= 0 or dy ~= 0 then
        local old = bounds(drag.win)
        screen.copy(old.x, old.y, old.w, old.h, dx, dy)
        drag.win.x, drag.win.y = nx, ny
        invalidateExposed(old, bounds(drag.win))
      end
      return true
    elseif (ev == "drop" or ev == "touch") and windows.dragging then
      windows.dragging = nil
      invalidateTaskbar()
      return true
    elseif ev == "touch" then
      local x, y = sig[3], sig[4]
      local win, part = hitWindow(x, y)
      if not win then return false end
      windows.bring(win)
      if part == "close" then
        windows.close(win)
      elseif part == "min" then
        windows.minimize(win)
      elseif part == "title" then
        windows.dragging = {win = win, dx = x - win.x, dy = y - win.y}
      else
        handleContent(win, x, y)
      end
      return true
    elseif ev == "scroll" then
      local x, y, dir = sig[3], sig[4], sig[5] or 0
      local win = hitWindow(x, y)
      if win and (win.kind == "apps" or win.kind == "files") then
        win.selected = math.max(1, win.selected + (dir > 0 and -1 or 1))
        invalidateWin(win)
        return true
      elseif win and win.kind == "taskmgr" then
        win.taskSelected = math.max(1, win.taskSelected + (dir > 0 and -1 or 1))
        invalidateWin(win)
        return true
      elseif win and win.kind == "textedit" then
        local _, _, _, ah = textArea(win)
        local maxScroll = math.max(0, #win.lines - ah)
        win.textScroll = math.max(0, math.min(maxScroll, (win.textScroll or 0) + (dir > 0 and -3 or 3)))
        invalidateWin(win)
        return true
      elseif win and win.kind == "terminal" then
        ensureTerminal(win)
        local maxScroll = math.max(0, #win.termLines - termRows(win))
        win.termScroll = math.max(0, math.min(maxScroll, (win.termScroll or 0) + (dir > 0 and -3 or 3)))
        invalidateWin(win)
        return true
      end
    end
    return false
  end

  function windows.tick(now)
    local sec = math.floor(now or 0)
    if sec == windows.lastSystemTick then return end
    windows.lastSystemTick = sec
    for _, win in ipairs(windows.list) do
      if (win.kind == "system" or win.kind == "taskmgr") and not win.minimized then invalidateWin(win) end
    end
  end

  return windows
end
