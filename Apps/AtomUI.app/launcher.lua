return function(state)
  local fs = require("filesystem")
  local proc = require("process")
  local unicode = require("unicode")

  local okLauncher, appRunner = pcall(require, "applauncher")

  local screen = state.screen
  local C = state.theme.color
  local L = state.theme.layout
  local S = state.theme.symbol
  local ui = state.widgets

  local launcher = {
    open = false,
    query = "",
    selected = 1,
    scroll = 0,
    items = nil
  }

  local function trimSlash(path)
    path = tostring(path or "")
    while #path > 1 and path:sub(-1) == "/" do path = path:sub(1, -2) end
    return path
  end

  local function appLabel(name)
    return (name:gsub("%.app$", ""))
  end

  local function readAtomApp(package)
    local path = "/Apps/" .. package .. "/atomapp.lua"
    local code = fs.readAll(path)
    if not code then return nil end
    local chunk = load(code, "=" .. path, "bt", _ENV)
    if not chunk then return nil end
    local ok, meta = pcall(chunk)
    if ok and type(meta) == "table" then return meta end
    return nil
  end

  local function lower(text)
    return tostring(text or ""):lower()
  end

  local function buildItems()
    local out = {}

    local packages = {}
    for _, entry in ipairs(fs.list("/Apps") or {}) do
      local clean = trimSlash(entry)
      if clean:match("%.app$") and clean ~= "AtomUI.app" then
        packages[#packages + 1] = clean
      end
    end
    table.sort(packages)

    for i, package in ipairs(packages) do
      local meta = readAtomApp(package)
      if meta and meta.native and meta.kind then
        out[#out + 1] = {
          label = meta.label or appLabel(package),
          glyph = meta.glyph or S.app,
          tint = meta.tint or ((i % 2 == 0) and C.accent or C.selected),
          kind = meta.kind,
          package = package,
          native = true
        }
      else
        out[#out + 1] = {
          label = appLabel(package),
          glyph = S.app,
          tint = (i % 2 == 0) and C.accent or C.selected,
          package = package
        }
      end
    end

    return out
  end

  local function allItems()
    if not launcher.items then launcher.items = buildItems() end
    return launcher.items
  end

  local function filteredItems()
    local q = lower(launcher.query)
    local out = {}
    for _, item in ipairs(allItems()) do
      if q == "" or lower(item.label):find(q, 1, true) then
        out[#out + 1] = item
      end
    end
    if launcher.selected > #out then launcher.selected = math.max(1, #out) end
    return out
  end

  local function layout()
    local margin = 4
    local cellW, cellH = L.launcherCellW, L.launcherCellH
    local cols = math.max(1, math.floor((state.w - margin * 2) / cellW))
    local startX = math.floor((state.w - cols * cellW) / 2) + 1
    local startY = 8
    local rows = math.max(1, math.floor((state.h - L.taskbarH - startY) / cellH))
    return cols, rows, startX, startY, cellW, cellH
  end

  local function invalidate()
    if state.desktop then state.desktop.invalidateAll() end
  end

  local function intersectsClip(x, y, w, h)
    local c = screen.clip
    if not c then return true end
    return not (x + w - 1 < c.x or y + h - 1 < c.y or x > c.x + c.w - 1 or y > c.y + c.h - 1)
  end

  local function ensureVisible()
    local cols, rows = layout()
    local row = math.floor((launcher.selected - 1) / cols)
    if row < launcher.scroll then launcher.scroll = row end
    if row >= launcher.scroll + rows then launcher.scroll = row - rows + 1 end
    if launcher.scroll < 0 then launcher.scroll = 0 end
  end

  function launcher.show()
    launcher.items = buildItems()
    launcher.open = true
    launcher.query = ""
    launcher.selected = 1
    launcher.scroll = 0
    invalidate()
  end

  function launcher.hide()
    if not launcher.open then return end
    launcher.open = false
    invalidate()
  end

  function launcher.toggle()
    if launcher.open then launcher.hide() else launcher.show() end
  end

  function launcher.refresh()
    launcher.items = nil
    if launcher.open then invalidate() end
  end

  local function launchPackage(package)
    local path = "/Apps/" .. package
    launcher.hide()

    if okLauncher and appRunner and state.api then
      if state.desktop then
        state.desktop.toast("Запуск " .. package, "ok")
        state.desktop.renderDirty()
        screen.flush()
      end
      local ctx = state.api.securityContext and state.api.securityContext() or nil
      local ok, err = appRunner.run(path, {}, state.api, _ENV, ctx)
      if state.desktop then state.desktop.invalidateAll() end
      if not ok and state.desktop then
        state.desktop.toast("Не удалось запустить " .. package .. ": " .. tostring(err), "danger")
      end
      return
    end

    local ok, err = proc.spawn(path)
    if state.desktop then
      state.desktop.toast(ok and ("Запущено " .. package) or ("Ошибка запуска: " .. tostring(err)), ok and "ok" or "danger")
    end
  end

  local function launchItem(item)
    if not item then return end
    if item.kind then
      launcher.hide()
      state.windows.open(item.kind, {package = item.package})
    elseif item.package then
      launchPackage(item.package)
    end
  end

  function launcher.render()
    if not launcher.open then return end
    if not intersectsClip(1, 2, state.w, state.h - L.taskbarH - 1) then return end

    screen.fill(1, 2, state.w, state.h - L.taskbarH - 1, " ", C.text, C.bg2)
    screen.text(4, 3, "Приложения", C.text, C.bg2)

    local q = launcher.query ~= "" and launcher.query or "поиск"
    local searchW = math.min(34, math.max(18, state.w - 16))
    local searchX = state.w - searchW - 3
    screen.fill(searchX, 3, searchW, 1, " ", C.subtext, C.field)
    screen.text(searchX + 2, 3, ui.cut(q, searchW - 4), launcher.query ~= "" and C.text or C.muted, C.field)

    local items = filteredItems()
    ensureVisible()
    local cols, rows, startX, startY, cellW, cellH = layout()
    local first = launcher.scroll * cols + 1
    local last = math.min(#items, first + rows * cols - 1)

    for i = first, last do
      local localIndex = i - first
      local col = localIndex % cols
      local row = math.floor(localIndex / cols)
      local x = startX + col * cellW
      local y = startY + row * cellH
      local item = items[i]
      ui.appIcon(x, y, item.label, item.glyph, item.tint, i == launcher.selected, C.bg2, cellW - 1)
    end

    if #items == 0 then
      screen.text(4, 8, "Ничего не найдено", C.muted, C.bg2)
    end
  end

  local function itemAt(x, y)
    local items = filteredItems()
    local cols, rows, startX, startY, cellW, cellH = layout()
    if x < startX or y < startY then return nil end
    local col = math.floor((x - startX) / cellW)
    local row = math.floor((y - startY) / cellH)
    if col < 0 or col >= cols or row < 0 or row >= rows then return nil end
    local index = (launcher.scroll + row) * cols + col + 1
    return items[index], index
  end

  function launcher.handle(sig)
    if not launcher.open then return false end
    local ev = sig[1]

    if ev == "touch" then
      local item, index = itemAt(sig[3], sig[4])
      if item then
        launcher.selected = index
        launchItem(item)
      else
        launcher.hide()
      end
      return true
    elseif ev == "scroll" then
      launcher.scroll = math.max(0, launcher.scroll + ((sig[5] or 0) > 0 and -1 or 1))
      launcher.selected = math.max(1, launcher.scroll * select(1, layout()) + 1)
      invalidate()
      return true
    elseif ev == "key_down" then
      local char, code = sig[3] or 0, sig[4] or 0
      local items = filteredItems()
      local cols = select(1, layout())

      if code == 1 then launcher.hide(); return true
      elseif code == 28 then launchItem(items[launcher.selected]); return true
      elseif code == 14 then
        if unicode.len(launcher.query) > 0 then
          launcher.query = unicode.sub(launcher.query, 1, unicode.len(launcher.query) - 1)
          launcher.selected, launcher.scroll = 1, 0
          invalidate()
        end
      elseif code == 203 then launcher.selected = math.max(1, launcher.selected - 1); ensureVisible(); invalidate()
      elseif code == 205 then launcher.selected = math.max(1, math.min(#items, launcher.selected + 1)); ensureVisible(); invalidate()
      elseif code == 200 then launcher.selected = math.max(1, launcher.selected - cols); ensureVisible(); invalidate()
      elseif code == 208 then launcher.selected = math.max(1, math.min(#items, launcher.selected + cols)); ensureVisible(); invalidate()
      elseif char >= 32 then
        launcher.query = launcher.query .. unicode.char(char)
        launcher.selected, launcher.scroll = 1, 0
        invalidate()
      end
      return true
    end

    return ev == "drag" or ev == "drop" or ev == "clipboard"
  end

  return launcher
end
