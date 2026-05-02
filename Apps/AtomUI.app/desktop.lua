return function(state)
  local sys = require("io")
  local unicode = require("unicode")

  local screen = state.screen
  local C = state.theme.color
  local L = state.theme.layout
  local S = state.theme.symbol
  local ui = state.widgets
  local windows = state.windows

  local desktop = {
    dirty = {},
    menuOpen = false,
    menuRect = nil,
    toastState = nil,
    lastClockText = nil
  }

  local START_W = 5

  local MENU_ITEMS = {
    {label = "AtomOS 1.0", icon = S.logo, disabled = true},
    {separator = true},
    {label = "Приложения", icon = S.app, action = "launcher"},
    {label = "TextEdit", icon = S.edit, action = "textedit"},
    {label = "Терминал", icon = S.terminal, action = "terminal"},
    {label = "Калькулятор", icon = S.calc, action = "calculator"},
    {label = "Диспетчер", icon = S.task, action = "taskmgr"},
    {label = "Файлы", icon = S.folder, action = "files"},
    {label = "Настройки", icon = S.gear, action = "settings"},
    {label = "О системе", icon = "i", action = "about"},
    {separator = true},
    {label = "Перерисовать", icon = "↻", action = "refresh"},
    {label = "Перезагрузка", icon = "↯", action = "reboot"},
    {separator = true},
    {label = "Выключить", icon = S.power, action = "shutdown"},
    {label = "Выйти в MES", icon = "×", action = "exit"}
  }

  local DESKTOP_ICONS = {
    {label = "Apps", title = "Приложения", glyph = S.app, launcher = true, tint = C.active, x = 4, y = 4},
    {label = "TextEdit", title = "TextEdit", glyph = S.edit, kind = "textedit", tint = C.info, x = 20, y = 4},
    {label = "Calc", title = "Калькулятор", glyph = S.calc, kind = "calculator", tint = C.ok, x = 36, y = 4},
    {label = "Files", title = "Файлы", glyph = S.folder, kind = "files", tint = C.warn, x = 4, y = 10},
    {label = "Tasks", title = "Диспетчер", glyph = S.task, kind = "taskmgr", tint = C.warn, x = 20, y = 10},
    {label = "Settings", title = "Настройки", glyph = S.gear, kind = "settings", tint = C.selected, x = 36, y = 10},
    {label = "Terminal", title = "Терминал", glyph = S.terminal, kind = "terminal", tint = C.info, x = 4, y = 16}
  }

  local function clipRect(x, y, w, h)
    local x1 = math.max(1, math.floor(x))
    local y1 = math.max(1, math.floor(y))
    local x2 = math.min(state.w, math.floor(x + w - 1))
    local y2 = math.min(state.h, math.floor(y + h - 1))
    if x2 < x1 or y2 < y1 then return nil end
    return {x = x1, y = y1, w = x2 - x1 + 1, h = y2 - y1 + 1}
  end

  local function contains(a, b)
    return b.x >= a.x and b.y >= a.y and
           b.x + b.w <= a.x + a.w and
           b.y + b.h <= a.y + a.h
  end

  function desktop.invalidate(x, y, w, h)
    local r = clipRect(x, y, w, h)
    if not r then return end

    local i = 1
    while i <= #desktop.dirty do
      local old = desktop.dirty[i]
      if contains(old, r) then return end
      if contains(r, old) then
        table.remove(desktop.dirty, i)
      else
        i = i + 1
      end
    end

    desktop.dirty[#desktop.dirty + 1] = r
    if #desktop.dirty > 48 then
      desktop.dirty = {{x = 1, y = 1, w = state.w, h = state.h}}
    end
  end

  function desktop.invalidateAll()
    desktop.invalidate(1, 1, state.w, state.h)
  end

  local function clockText()
    if sys.date and sys.time then
      local okTime, t = pcall(sys.time)
      if okTime and t then
        local okDate, text = pcall(sys.date, "%H:%M", t)
        if okDate and text then return text end
      end
    end
    local up = sys.uptime() or 0
    return string.format("%02d:%02d", math.floor(up / 3600) % 24, math.floor(up / 60) % 60)
  end

  local function currentUser()
    if state.api and state.api.getUser then
      local ok, user = pcall(state.api.getUser)
      if ok and user and user.name then return user.name end
    end
    return "atom"
  end

  local function intersectsClip(x, y, w, h)
    local c = screen.clip
    if not c then return true end
    return not (x + w - 1 < c.x or y + h - 1 < c.y or x > c.x + c.w - 1 or y > c.y + c.h - 1)
  end

  local function drawMenubar()
    if not intersectsClip(1, 1, state.w, 1) then return end
    screen.fill(1, 1, state.w, 1, " ", C.text, C.taskbar)
    screen.text(2, 1, "AtomOS", C.text, C.taskbar)
    screen.textRight(state.w - 1, 1, clockText(), C.text, C.taskbar)
    screen.textRight(state.w - 9, 1, ui.cut(currentUser(), 12), C.subtext, C.taskbar)
  end

  local function drawDesktopIcon(icon)
    if not intersectsClip(icon.x, icon.y, L.iconW, L.iconH) then return end
    ui.appIcon(icon.x, icon.y, icon.label, icon.glyph, icon.tint or C.accent, false, C.bg, L.iconW)
  end

  local function drawDesktopStatus()
    local w = math.min(42, math.max(30, math.floor(state.w / 4)))
    local x = state.w - w - 3
    local y = 4
    if x < 42 then return end
    if not intersectsClip(x, y, w, 4) then return end

    local total = sys.totalMemory() or 0
    local free = sys.freeMemory() or 0
    local used = math.max(0, total - free)
    local energy = sys.energy() or 0
    local maxEnergy = sys.maxEnergy() or 0

    screen.fill(x, y, w, 4, " ", C.text, C.bg)
    screen.text(x, y, "MEM", C.subtext, C.bg)
    local memPct = ui.thinBar(x + 5, y, w - 11, used, total, C.info, C.bg)
    screen.textRight(x + w - 1, y, string.format("%3d%%", math.floor(memPct * 100 + 0.5)), C.text, C.bg)
    screen.text(x, y + 2, "PWR", C.subtext, C.bg)
    local pwrPct = ui.thinBar(x + 5, y + 2, w - 11, energy, maxEnergy, C.ok, C.bg)
    screen.textRight(x + w - 1, y + 2, string.format("%3d%%", math.floor(pwrPct * 100 + 0.5)), C.text, C.bg)
  end

  local function drawDesktop()
    screen.fill(1, 1, state.w, state.h, " ", C.text, C.bg)
    drawMenubar()
    for _, icon in ipairs(DESKTOP_ICONS) do drawDesktopIcon(icon) end
    drawDesktopStatus()
  end

  local function drawTaskbar()
    local y = state.h - L.taskbarH + 1
    if not intersectsClip(1, y, state.w, L.taskbarH) then return end
    screen.fill(1, y, state.w, L.taskbarH, " ", C.text, C.taskbar)
    ui.button3(1, y, START_W, "", desktop.menuOpen, S.logo)

    local x = START_W + 2
    for i, win in ipairs(windows.list) do
      local label = (win.minimized and (S.down .. " ") or "") .. win.title
      local bw = math.min(22, math.max(12, unicode.len(label) + 5))
      if x + bw >= state.w - 10 then break end
      ui.button3(x, y, bw, ui.cut(label, bw - 5), windows.isTop(win), "")
      x = x + bw + 1
    end
  end

  local function menuHeight()
    local h = L.popupPad * 2
    for _, item in ipairs(MENU_ITEMS) do
      h = h + ui.menuItemHeight(item)
    end
    return h
  end

  local function computeMenuRect()
    local h = menuHeight()
    local y = state.h - L.taskbarH + 1 - h
    if y < 2 then y = 2 end
    return {x = 1, y = y, w = L.menuW, h = h}
  end

  local function drawMenu()
    if not desktop.menuOpen or not desktop.menuRect then return end
    local r = desktop.menuRect
    if not intersectsClip(r.x, r.y, r.w, r.h) then return end
    screen.fill(r.x, r.y, r.w, r.h, " ", C.text, C.accent)
    local row = r.y + L.popupPad
    for _, item in ipairs(MENU_ITEMS) do
      row = row + ui.menuItem(r.x, row, r.w, item, false)
    end
  end

  local function hitMenu(x, y)
    if not desktop.menuRect then return nil end
    local r = desktop.menuRect
    if x < r.x or y < r.y or x >= r.x + r.w or y >= r.y + r.h then return nil end
    local row = r.y + L.popupPad
    for _, item in ipairs(MENU_ITEMS) do
      local ih = ui.menuItemHeight(item)
      if not item.separator and not item.disabled then
        if y >= row and y < row + ih then return item.action end
      end
      row = row + ih
    end
    return nil
  end

  local function openMenu()
    desktop.menuOpen = true
    desktop.menuRect = computeMenuRect()
    local r = desktop.menuRect
    desktop.invalidate(r.x, r.y, r.w + 2, r.h)
    desktop.invalidate(1, state.h - L.taskbarH + 1, START_W, L.taskbarH)
  end

  local function closeMenu()
    if desktop.menuRect then
      local r = desktop.menuRect
      desktop.invalidate(r.x, r.y, r.w + 2, r.h)
    end
    desktop.menuOpen = false
    desktop.menuRect = nil
    desktop.invalidate(1, state.h - L.taskbarH + 1, START_W, L.taskbarH)
  end

  local function hitDesktopIcon(x, y)
    for _, icon in ipairs(DESKTOP_ICONS) do
      if x >= icon.x and x < icon.x + L.iconW and y >= icon.y and y < icon.y + L.iconH then
        return icon
      end
    end
    return nil
  end

  function desktop.toast(text, kind)
    local w = math.min(state.w - 4, math.max(24, unicode.len(text) + 4))
    desktop.toastState = {
      text = text,
      kind = kind,
      x = math.floor((state.w - w) / 2) + 1,
      y = state.h - L.taskbarH,
      w = w,
      untilTime = (sys.uptime() or 0) + 3
    }
    desktop.invalidate(desktop.toastState.x, desktop.toastState.y, desktop.toastState.w, 1)
  end

  local function drawToast()
    if not desktop.toastState then return end
    local t = desktop.toastState
    if not intersectsClip(t.x, t.y, t.w, 1) then return end
    ui.toast(t.x, t.y, t.w, t.text, t.kind)
  end

  local function power(reboot)
    local ok, err = sys.shutdown(reboot)
    if not ok and err then
      desktop.toast((reboot and "reboot" or "shutdown") .. ": " .. tostring(err), "danger")
    end
  end

  local function perform(action)
    if action == "about" then windows.open("about")
    elseif action == "launcher" then if state.launcher then state.launcher.show() end
    elseif action == "textedit" then windows.open("textedit")
    elseif action == "terminal" then windows.open("terminal")
    elseif action == "calculator" then windows.open("calculator")
    elseif action == "taskmgr" then windows.open("taskmgr")
    elseif action == "settings" then windows.open("settings")
    elseif action == "apps" then windows.open("apps")
    elseif action == "files" then windows.open("files")
    elseif action == "system" then windows.open("system")
    elseif action == "refresh" then
      if state.launcher and state.launcher.refresh then state.launcher.refresh() end
      desktop.invalidateAll()
    elseif action == "reboot" then power(true)
    elseif action == "shutdown" then power(false)
    elseif action == "exit" then state.running = false end
  end

  local function hitTaskbar(x, y)
    local taskY = state.h - L.taskbarH + 1
    if y < taskY then return false end
    if x >= 1 and x < 1 + START_W then
      if desktop.menuOpen then closeMenu() else openMenu() end
      return true
    end

    local bx = START_W + 2
    for _, win in ipairs(windows.list) do
      local label = (win.minimized and (S.down .. " ") or "") .. win.title
      local bw = math.min(22, math.max(12, unicode.len(label) + 5))
      if x >= bx and x < bx + bw then
        if windows.isTop(win) then
          windows.minimize(win)
        else
          windows.restore(win)
        end
        return true
      end
      bx = bx + bw + 1
    end
    return true
  end

  local function renderRegion(r)
    screen.withClip(r, function()
      drawDesktop()
      windows.renderAll()
      drawTaskbar()
      drawMenu()
      if state.launcher then state.launcher.render() end
      drawToast()
    end)
  end

  function desktop.renderDirty()
    if #desktop.dirty == 0 then return end
    local list = desktop.dirty
    desktop.dirty = {}
    for _, r in ipairs(list) do renderRegion(r) end
  end

  function desktop.handle(sig)
    local ev = sig[1]
    if not ev then return end

    if ev == "atom_interrupt" then
      if state.launcher and state.launcher.open then state.launcher.hide(); return end
      if desktop.menuOpen then closeMenu() else state.running = false end
      return
    end

    if state.launcher and state.launcher.handle(sig) then return end

    if ev == "key_down" then
      local code = sig[4]
      if windows.handle(sig) then return end
      if code == 1 then
        if desktop.menuOpen then closeMenu() else state.running = false end
      end
      return
    end

    if ev == "drag" or ev == "drop" or ev == "scroll" then
      windows.handle(sig)
      return
    end

    if ev ~= "touch" then return end

    local x, y = sig[3], sig[4]
    if desktop.menuOpen then
      local action = hitMenu(x, y)
      closeMenu()
      if action then perform(action) end
      return
    end

    if y >= state.h - L.taskbarH + 1 then
      hitTaskbar(x, y)
      return
    end

    if windows.handle(sig) then return end

    local icon = hitDesktopIcon(x, y)
    if icon then
      if icon.launcher and state.launcher then state.launcher.show()
      else windows.open(icon.kind) end
    end
  end

  function desktop.tick()
    local now = sys.uptime() or 0
    local text = clockText()
    if text ~= desktop.lastClockText then
      desktop.lastClockText = text
      desktop.invalidate(1, 1, state.w, 1)
      desktop.invalidate(state.w - 46, 4, 44, 4)
    end

    windows.tick(now)

    if desktop.toastState and now >= desktop.toastState.untilTime then
      local t = desktop.toastState
      desktop.toastState = nil
      desktop.invalidate(t.x, t.y, t.w, 1)
    end
  end

  function desktop.init()
    state.desktop = desktop
    screen.clear(C.bg)
    screen.markAll()
    desktop.invalidateAll()
  end

  function desktop.shutdown()
    if state.api and state.api.clear then
      pcall(state.api.clear)
      desktop.dirty = {}
    else
      screen.clear(C.bg)
      screen.markAll()
      desktop.dirty = {}
    end
  end

  return desktop
end
