return function(state)
  local ui = {}
  local gpu = require("graphics")
  local unicode = require("unicode")
  
  local rowCache = {}
  local sidebarCache = {}

  ui.menus = {
    {name="File", x=2, items={"Save  ^S", "Close ^W", "Exit  ^Q"}},
    {name="Edit", x=8, items={"Find    ^F", "Replace ^H", "Goto    ^G"}},
    {name="View", x=14, items={"Sticky row", "Indent guides", "Find highlight", "Syntax color", "Scroll marks"}}
  }

  function ui.invalidateSidebar()
    sidebarCache = {}
  end

  function ui.invalidateRows(y1, y2)
    local from = math.max(1, (y1 or 2) - 1)
    local to = math.min(state.h - 2, (y2 or state.h - 1) - 1)
    for i = from, to do
      rowCache[i] = nil
      sidebarCache[i] = nil
    end
    state.sbCache = nil
  end

  function ui.invalidateLine(line)
    if not line then return end
    local i = line - (state.scrollY or 0)
    if i >= 1 and i <= state.h - 2 then rowCache[i] = nil end
  end

  function ui.invalidateEditor()
    rowCache = {}
    state.sbCache = nil
    state.stickyDrawKey = nil
    state.presentFull = true
  end

  function ui.canBufferedFrame()
    local db = state.doublebuffer
    return db and type(db.supported) == "function" and db.supported()
  end

  function ui.ensureFrameBuffer()
    local db = state.doublebuffer
    if not ui.canBufferedFrame() then return nil end
    local frame = state.frameBuffer
    if not frame or frame.w ~= state.w or frame.h ~= state.h or not frame.id then
      if frame and db.free then db.free(frame) end
      frame = db.create(state.w, state.h)
      state.frameBuffer = frame
    end
    return frame
  end

  function ui.beginBufferedFrame()
    local db = state.doublebuffer
    local frame = ui.ensureFrameBuffer()
    if not db or not frame then return false end
    local ok = db.begin(frame, true, state.syntax.C.BG)
    if not ok then return false end
    state.frameActive = frame
    return true
  end

  function ui.endBufferedFrame()
    local db, frame = state.doublebuffer, state.frameActive
    state.frameActive = nil
    if db and frame then db.commit(frame) end
  end

  function ui.menuAt(x)
    for i, m in ipairs(ui.menus) do
      local w = unicode.len(m.name) + 2
      if x >= m.x and x < m.x + w then return i end
    end
    return nil
  end

  function ui.menuItems(idx)
    local m = ui.menus[idx]
    if not m then return {} end
    if idx ~= 3 then return m.items end
    return {
      (state.showSticky ~= false and "[x] " or "[ ] ") .. "Sticky row",
      (state.showGuides ~= false and "[x] " or "[ ] ") .. "Indent guides",
      (state.showFindHighlight ~= false and "[x] " or "[ ] ") .. "Find highlight",
      (state.showSyntax ~= false and "[x] " or "[ ] ") .. "Syntax color",
      (state.showScrollMarks ~= false and "[x] " or "[ ] ") .. "Scroll marks"
    }
  end

  function ui.menuWidth(idx)
    local w = 10
    for _, item in ipairs(ui.menuItems(idx)) do
      w = math.max(w, unicode.len(item) + 2)
    end
    return w
  end

  function ui.clear()
    if state.frameBuffer and state.doublebuffer and state.doublebuffer.free then
      state.doublebuffer.free(state.frameBuffer)
      state.frameBuffer = nil
    end
    if state.api then state.api.clear()
    else gpu.setBackground(0x000000); gpu.fill(1, 1, state.w, state.h, " ") end
  end

  function ui.popupSpan(y)
    local p = state.popup
    if p and y >= p.y and y < p.y + p.h then
      return p.x, p.x + p.w - 1
    end
    return nil, nil
  end

  function ui.isStickyRow(y)
    local count = state.stickyCount or 0
    return state.showSticky ~= false and count > 0 and y >= 2 and y < 2 + count
  end

  function ui.underlayBg(y, fallback)
    if not state.target then return fallback end
    local li = y - 1 + (state.scrollY or 0)
    if li < 1 or li > #state.buffer then return fallback end
    local sr1, sc1, sr2, sc2 = state.core.selNorm()
    if sr1 and li >= sr1 and li <= sr2 then return state.syntax.C.SEL_BG end
    if li == state.cy then return state.syntax.C.CUR_BG end
    return fallback
  end

  function ui.fillClipped(x, y, w, bg)
    if w <= 0 then return end
    local bx1, bx2 = ui.popupSpan(y)
    gpu.setBackground(bg)
    if not bx1 then
      gpu.fill(x, y, w, 1, " ")
      return
    end
    local x2 = x + w - 1
    if x < bx1 then gpu.fill(x, y, math.min(x2, bx1 - 1) - x + 1, 1, " ") end
    if x2 > bx2 then
      local rx = math.max(x, bx2 + 1)
      gpu.fill(rx, y, x2 - rx + 1, 1, " ")
    end
  end

  function ui.setClipped(x, y, text, fg, bg)
    if not text or text == "" then return end
    local len = unicode.len(text)
    local bx1, bx2 = ui.popupSpan(y)
    gpu.setForeground(fg)
    gpu.setBackground(bg)
    if not bx1 or x > bx2 or x + len - 1 < bx1 then
      gpu.set(x, y, text)
      return
    end
    if x < bx1 then
      local n = bx1 - x
      if n > 0 then gpu.set(x, y, unicode.sub(text, 1, n)) end
    end
    if x + len - 1 > bx2 then
      local start = bx2 - x + 2
      if start <= len then gpu.set(bx2 + 1, y, unicode.sub(text, start)) end
    end
  end

  function ui.drawMenu()
    local key = tostring(state.menuActive) .. ":" .. tostring(state.menuIdx)
    if state.menuBarKey == key then return end
    state.menuBarKey = key
    gpu.setBackground(state.syntax.C.BAR_BG)
    gpu.fill(1, 1, state.w, 1, " ")
    for i, m in ipairs(ui.menus) do
      if state.menuActive and state.menuIdx == i then gpu.setBackground(state.syntax.C.SEL_BG)
      else gpu.setBackground(state.syntax.C.BAR_BG) end
      gpu.setForeground(state.syntax.C.KEY)
      gpu.set(m.x, 1, " " .. m.name .. " ")
    end
    gpu.setBackground(state.syntax.C.BAR_BG)
  end

  function ui.drawDropdown()
    if not state.menuActive then return end
    local m = ui.menus[state.menuIdx]
    local items = ui.menuItems(state.menuIdx)
    local w = ui.menuWidth(state.menuIdx)
    for i, item in ipairs(items) do
      gpu.setBackground(state.itemIdx == i and state.syntax.C.MENU_SEL_BG or state.syntax.C.MENU_BG)
      gpu.fill(m.x, 1 + i, w, 1, " ")
      gpu.setForeground(state.syntax.C.FG)
      gpu.set(m.x + 1, 1 + i, unicode.sub(item .. string.rep(" ", w), 1, w - 2))
    end
  end

  function ui.drawPopup()
    if not state.popup then return end
    local p = state.popup
    local key = p.type .. ":" .. tostring(p.focused) .. ":" .. tostring(p.text) .. ":" .. tostring(p.active)
    if p.fields then
      for _, field in ipairs(p.fields) do key = key .. ":" .. tostring(field.text) end
      key = key .. ":" .. tostring(p.replaced) .. ":" .. tostring(p.total)
    elseif p.type == "find" then
      local term = p.text or ""
      local total = term ~= "" and #state.core.findMatches(term) or 0
      local idx = term == state.findTerm and (state.findIndex or 0) or 0
      key = key .. ":" .. tostring(idx) .. ":" .. tostring(total)
    end
    if p.renderKey == key and not p.dirty then return end
    p.renderKey, p.dirty = key, false

    local framed = p.type ~= "new" and p.type ~= "quickopen"
    local basePanelBg = p.type == "new" and state.syntax.C.NEW_BG or state.syntax.C.POPUP_BG
    gpu.setBackground(basePanelBg)
    if framed then
      gpu.setForeground(state.syntax.C.DIM)
      gpu.set(p.x, p.y, "┌" .. string.rep("─", p.w - 2) .. "┐")
      for i = 1, p.h - 2 do
        local rowBg = ui.underlayBg(p.y + i, basePanelBg)
        gpu.setBackground(rowBg)
        gpu.set(p.x, p.y + i, "│" .. string.rep(" ", p.w - 2) .. "│")
      end
      gpu.setBackground(basePanelBg)
      gpu.set(p.x, p.y + p.h - 1, "└" .. string.rep("─", p.w - 2) .. "┘")
    else
      for i = 0, p.h - 1 do
        gpu.setBackground(basePanelBg)
        gpu.fill(p.x, p.y + i, p.w, 1, " ")
      end
    end

    local function rowPanelBg(row)
      return framed and ui.underlayBg(row, basePanelBg) or basePanelBg
    end

    local function drawInputAt(inputX, row, inputW, text, active, placeholder)
      gpu.setBackground(active and state.syntax.C.INPUT_FOCUS_BG or state.syntax.C.INPUT_BG)
      gpu.fill(inputX, row, inputW, 1, " ")
      local empty = (text or "") == ""
      gpu.setForeground((not active and empty and placeholder) and state.syntax.C.DIM or (active and state.syntax.C.KEY or state.syntax.C.FG))
      local innerW = math.max(1, inputW - 2)
      local txt = (empty and not active and placeholder) and placeholder or (text or "")
      txt = txt .. (active and "_" or "")
      if unicode.len(txt) > innerW then txt = unicode.sub(txt, -innerW) end
      gpu.set(inputX + 1, row, txt)
    end

    local function drawInput(row, text, active)
      drawInputAt(p.x + 2, row, p.w - 4, text, active)
    end

    local function drawPanelText(x, y, text, fg)
      gpu.setBackground(rowPanelBg(y))
      gpu.setForeground(fg or state.syntax.C.HINT)
      gpu.set(x, y, text)
    end

    local function clearPanelRow(y, x, w)
      gpu.setBackground(rowPanelBg(y))
      gpu.fill(x, y, w, 1, " ")
    end

    if p.type == "find" then
      local term = p.text or ""
      local total = term ~= "" and #state.core.findMatches(term) or 0
      local idx = term == state.findTerm and (state.findIndex or 0) or 0
      local stat = total == 0 and "No results" or string.format("%d of %d", idx, total)
      local inputW = math.max(10, p.w - 24)
      p.inputX, p.inputY, p.inputW = p.x + 4, p.y + 1, inputW
      p.prevX, p.nextX = p.x + p.w - 8, p.x + p.w - 5

      clearPanelRow(p.y + 1, p.x + 1, p.w - 2)
      drawPanelText(p.x + 2, p.y + 1, ">", state.syntax.C.DIM)

      drawInputAt(p.inputX, p.inputY, inputW, term, p.focused ~= false, "Find")

      gpu.setBackground(rowPanelBg(p.y + 1))
      gpu.setForeground(state.syntax.C.DIM)
      gpu.set(p.inputX + inputW + 1, p.y + 1, unicode.sub(stat .. string.rep(" ", 10), 1, 10))
      gpu.setForeground(state.syntax.C.FG)
      gpu.set(p.prevX, p.y + 1, "↑")
      gpu.set(p.nextX, p.y + 1, "↓")
      gpu.set(p.x + p.w - 2, p.y + 1, "≡")
      return
    end

    if p.type == "quickopen" then
      local matches = state.core.quickMatches(p.text or "")
      p.matches = matches
      if #matches == 0 then p.active = 0
      else
        p.active = math.max(1, math.min(p.active or 1, #matches))
      end
      clearPanelRow(p.y, p.x, p.w)
      drawInputAt(p.x + 2, p.y, p.w - 4, p.text or "", p.focused ~= false, "Open file")
      for i = 1, p.h - 1 do
        local row = p.y + i
        local match = matches[i]
        gpu.setBackground(match and p.active == i and state.syntax.C.MENU_SEL_BG or basePanelBg)
        gpu.fill(p.x, row, p.w, 1, " ")
        if match then
          gpu.setForeground(state.core.isDirty(match.path) and state.syntax.C.DIRTY or state.syntax.C.FG)
          gpu.set(p.x + 2, row, unicode.sub(match.text, 1, p.w - 4))
        end
      end
      return
    end

    if p.type == "replace" and p.fields then
      local findText = p.fields[1].text or ""
      local replText = p.fields[2].text or ""
      local total = p.total
      if total == nil and findText ~= "" then total = #state.core.findMatches(findText) end
      total = total or 0
      local stat = total == 0 and "0/0" or string.format("%d/%d", p.replaced or 0, total)
      local inputW = math.max(10, p.w - 24)
      p.findInputX, p.findInputY, p.findInputW = p.x + 4, p.y + 1, inputW
      p.replInputX, p.replInputY, p.replInputW = p.x + 4, p.y + 2, inputW
      p.prevX, p.nextX = p.x + p.w - 8, p.x + p.w - 5

      clearPanelRow(p.y + 1, p.x + 1, p.w - 2)
      clearPanelRow(p.y + 2, p.x + 1, p.w - 2)
      drawPanelText(p.x + 2, p.y + 1, ">", state.syntax.C.DIM)
      drawPanelText(p.x + 2, p.y + 2, " ", state.syntax.C.DIM)
      drawInputAt(p.findInputX, p.findInputY, inputW, findText, p.focused ~= false and p.active == 1, "Find")
      drawInputAt(p.replInputX, p.replInputY, inputW, replText, p.focused ~= false and p.active == 2, "Replace")

      gpu.setBackground(rowPanelBg(p.y + 1))
      gpu.setForeground(state.syntax.C.DIM)
      gpu.set(p.findInputX + inputW + 1, p.y + 1, unicode.sub(stat .. string.rep(" ", 10), 1, 10))
      gpu.setForeground(state.syntax.C.FG)
      gpu.set(p.prevX, p.y + 1, "↑")
      gpu.set(p.nextX, p.y + 1, "↓")
      gpu.set(p.x + p.w - 2, p.y + 1, "≡")

      gpu.setBackground(rowPanelBg(p.y + 2))
      gpu.setForeground(state.syntax.C.DIM)
      gpu.set(p.findInputX + inputW + 1, p.y + 2, "AB")
      return
    end

    if p.fields then
      for i, field in ipairs(p.fields) do
        local labelY = p.y + (i - 1) * 2 + 1
        drawPanelText(p.x + 2, labelY, field.label)
        drawInput(labelY + 1, field.text or "", p.focused ~= false and p.active == i)
      end
      return
    end

    drawPanelText(p.x + 2, p.y + 1, p.label, state.syntax.C.HINT)
    drawInput(p.y + 3, p.text or "", p.focused ~= false)
    if p.type == "find" then
      local term = p.text or ""
      local total = term ~= "" and #state.core.findMatches(term) or 0
      local idx = term == state.findTerm and (state.findIndex or 0) or 0
      local stat = string.format("%d/%d", idx, total)
      gpu.setBackground(rowPanelBg(p.y + p.h - 2))
      gpu.setForeground(state.syntax.C.DIM)
      gpu.set(p.x + p.w - unicode.len(stat) - 2, p.y + p.h - 2, stat)
    end
  end

  function ui.drawStatus()
    gpu.setBackground(state.syntax.C.BAR_BG)
    gpu.fill(1, state.h, state.w, 1, " ")
    if state.statusMsg then
      gpu.setForeground(state.syntax.C.OK)
      gpu.set(2, state.h, state.statusMsg)
    elseif not state.target then
      gpu.setForeground(state.syntax.C.DIM)
      gpu.set(2, state.h, "Workspace: " .. (state.workspace or "/"))
    elseif state.sel then
      local sr1, sc1, sr2, sc2 = state.core.selNorm()
      gpu.setForeground(state.syntax.C.HINT)
      if sr1 == sr2 then gpu.set(2, state.h, string.format("SEL %d chars  Ln %d/%d  %s", sc2 - sc1, state.cy, #state.buffer, state.modified and "[+]" or ""))
      else gpu.set(2, state.h, string.format("SEL %d lines  Ln %d/%d  %s", sr2 - sr1 + 1, state.cy, #state.buffer, state.modified and "[+]" or "")) end
    else
      gpu.setForeground(state.syntax.C.DIM)
      local fileStr = state.target and state.target:match("([^/]+)$") or "No File"
      gpu.set(2, state.h, string.format("%s  Ln %d/%d  Col %d  %s", fileStr, state.cy, #state.buffer, state.cx, state.modified and "[+]" or ""))
    end
  end

  function ui.isOverlayRow(y)
    if ui.isStickyRow(y) then return true end
    local p = state.popup
    if p and y >= p.y and y < p.y + p.h then return true end
    return false
  end

  function ui.adjustPopupForSticky()
    local p = state.popup
    if not p or p.type == "new" then return end
    local targetY = 2 + (state.stickyCount or 0)
    targetY = math.max(2, math.min(targetY, state.h - p.h))
    if p.y == targetY then return end
    ui.invalidateRows(p.y, p.y + p.h - 1)
    p.y = targetY
    p.dirty = true
    ui.invalidateRows(p.y, p.y + p.h - 1)
  end

  function ui.shiftEditor(dir)
    if not state.target then return end
    local edH = state.h - 2
    local sx = state.sidebarW + 1
    local cw = state.w - state.sidebarW - 1
    if math.abs(dir) < edH then
      if not state.popup then
        local topY = 2 + (state.stickyCount or 0)
        local copyH = state.h - topY
        if copyH <= 0 or math.abs(dir) >= copyH then rowCache = {}; return end
        if dir > 0 then gpu.copy(sx, topY + dir, cw, copyH - dir, 0, -dir)
        else gpu.copy(sx, topY, cw, copyH + dir, 0, -dir) end
        local newCache = {}
        for i = 1, edH do
          local oldI = i + dir
          if oldI >= 1 and oldI <= edH and not ui.isStickyRow(i + 1) and not ui.isStickyRow(oldI + 1) then
            newCache[i] = rowCache[oldI]
          end
        end
        rowCache = newCache
        return
      end
      local destStart = dir > 0 and 2 or (2 - dir)
      local destEnd = dir > 0 and (state.h - 1 - dir) or (state.h - 1)
      local runStart = nil
      for y = destStart, destEnd do
        local canCopy = not ui.isOverlayRow(y) and not ui.isOverlayRow(y + dir)
        if canCopy and not runStart then runStart = y end
        if (not canCopy or y == destEnd) and runStart then
          local runEnd = canCopy and y or (y - 1)
          gpu.copy(sx, runStart + dir, cw, runEnd - runStart + 1, 0, -dir)
          runStart = nil
        end
      end
      local newCache = {}
      for i = 1, edH do
        local oldI = i + dir
        if oldI >= 1 and oldI <= edH and not ui.isOverlayRow(i + 1) and not ui.isOverlayRow(oldI + 1) then
          newCache[i] = rowCache[oldI]
        end
      end
      rowCache = newCache
    else rowCache = {} end
  end

  function ui.clamp()
    if not state.target then return end
    local edH = state.h - 2
    local contentW = state.w - state.gutterW - state.sidebarW - 1
    local oldY = state.scrollY
    local topPad = state.stickyCount or 0
    if state.cy - state.scrollY > edH then state.scrollY = state.cy - edH end
    if state.cy - state.scrollY < 1 + topPad then state.scrollY = math.max(0, state.cy - 1 - topPad) end
    local dy = state.scrollY - oldY
    if dy ~= 0 then ui.shiftEditor(dy) end
    if state.cx - state.scrollX > contentW then state.scrollX = state.cx - contentW end
    if state.cx - state.scrollX < 1        then state.scrollX = state.cx - 1        end
  end

  function ui.centerCursor(bufferedJump)
    if not state.target then return end
    local edH = state.h - 2
    local contentW = state.w - state.gutterW - state.sidebarW - 1
    local oldY = state.scrollY
    local maxScroll = math.max(0, #state.buffer - edH)
    local topPad = state.stickyCount or 0
    local visibleH = math.max(1, edH - topPad)
    state.scrollY = math.max(0, math.min(maxScroll, state.cy - topPad - math.floor(visibleH / 2)))
    local dy = state.scrollY - oldY
    if dy ~= 0 then
      if bufferedJump and ui.canBufferedFrame() then
        rowCache = {}
        state.sbCache = nil
        state.presentFull = true
      else
        ui.shiftEditor(dy)
      end
    end
    if state.cx - state.scrollX > contentW then state.scrollX = state.cx - contentW end
    if state.cx - state.scrollX < 1        then state.scrollX = state.cx - 1        end
  end

  function ui.renderSidebar(force)
    if state.sidebarW <= 0 then sidebarCache = {}; return end
    if force then sidebarCache = {} end
    local edH = state.h - 2
    for i = 1, edH do
      local idx = i + (state.sidebarScroll or 0)
      local node = state.visibleNodes and state.visibleNodes[idx]
      local isSel = node and (state.target == node.path) or false
      local isExp = node and node.isDir and state.expandedDirs[node.path] or false
      local isDirty = node and not node.isDir and state.core.isDirty(node.path) or false
      local cacheStr = node and (node.path .. node.name .. tostring(node.depth) .. tostring(isSel) .. tostring(isExp) .. tostring(isDirty)) or "empty"
      
      if sidebarCache[i] ~= cacheStr then
        gpu.setBackground(isSel and state.syntax.C.SEL_BG or state.syntax.C.BG)
        gpu.fill(1, i + 1, state.sidebarW - 1, 1, " ")
        if node then
          local indent = node.depth * 2
          local prefix = node.isDir and (isExp and "v " or "> ") or "  "
          local text = string.rep(" ", indent) .. prefix .. node.name
          gpu.setForeground(node.isDir and state.syntax.C.HINT or state.syntax.C.FG)
          gpu.set(2, i + 1, unicode.sub(text, 1, state.sidebarW - 5))
          if node.isDir then
            gpu.setBackground(state.syntax.C.BAR_BG)
            gpu.setForeground(state.syntax.C.OK)
            gpu.set(state.sidebarW - 3, i + 1, " + ")
          elseif isDirty then
            gpu.setBackground(isSel and state.syntax.C.SEL_BG or state.syntax.C.BG)
            gpu.setForeground(state.syntax.C.DIRTY)
            gpu.set(state.sidebarW - 2, i + 1, "•")
          end
        end
        gpu.setBackground(state.syntax.C.BG)
        gpu.setForeground(state.syntax.C.DIM)
        gpu.set(state.sidebarW, i + 1, "│")
        sidebarCache[i] = cacheStr
      end
    end
  end

  function ui.renderScrollbar()
    if not state.target then return end
    local edH = state.h - 2
    local total = #state.buffer
    local sr1, sc1, sr2, sc2 = state.core.selNorm()
    local sbCacheStr = table.concat({
      state.scrollY, total, state.cy, sr1 or 0, sc1 or 0, sr2 or 0, sc2 or 0,
      state.findVersion or 0
    }, "_")
    if state.sbCache == sbCacheStr then return end
    state.sbCache = sbCacheStr
    
    gpu.setBackground(state.syntax.C.BG)
    gpu.setForeground(state.syntax.C.BAR_BG)
    gpu.fill(state.w, 2, 1, edH, "│")

    local thumbStart, thumbEnd = nil, nil
    if total > edH then
      local thumbH = math.max(1, math.floor((edH / total) * edH))
      local maxScroll = total - edH
      local thumbY = 1 + math.floor((state.scrollY / maxScroll) * (edH - thumbH))
      thumbStart, thumbEnd = 1 + thumbY, thumbY + thumbH
      gpu.setForeground(state.syntax.C.DIM)
      gpu.fill(state.w, thumbStart, 1, thumbH, "█")
    end

    local function lineToY(line)
      if total <= 1 then return 2 end
      return 2 + math.floor(((line - 1) / (total - 1)) * (edH - 1))
    end

    local function drawMarkY(y, color)
      gpu.setBackground(state.syntax.C.BG)
      gpu.setForeground(color)
      local onThumb = thumbStart and y >= thumbStart and y <= thumbEnd
      gpu.set(state.w, y, onThumb and "█" or "│")
    end

    local function drawMark(line, color)
      if not line or line < 1 or line > total then return end
      drawMarkY(lineToY(line), color)
    end

    if state.showScrollMarks ~= false and state.findTerm and state.findTerm ~= "" then
      local key = table.concat({state.findTerm, state.bufferVersion or 0, total, edH}, "_")
      local marks
      if state.findScrollMarksCache and state.findScrollMarksCache.key == key then
        marks = state.findScrollMarksCache.marks
      else
        local seen = {}
        marks = {}
        for _, match in ipairs(state.core.findMatches(state.findTerm)) do
          local y = lineToY(match.line)
          if not seen[y] then
            seen[y] = true
            marks[#marks + 1] = y
          end
        end
        state.findScrollMarksCache = {key = key, marks = marks}
      end
      for _, y in ipairs(marks) do
        drawMarkY(y, state.syntax.C.FIND_SCROLL)
      end
    end

    if state.showScrollMarks ~= false and sr1 then
      if sr2 - sr1 > edH * 2 then
        for y = lineToY(sr1), lineToY(sr2) do drawMarkY(y, state.syntax.C.SCROLL_MARK) end
      else
        for li = sr1, sr2 do drawMark(li, state.syntax.C.SCROLL_MARK) end
      end
    end
    if state.showScrollMarks ~= false then drawMark(state.cy, state.syntax.C.SCROLL_MARK) end
  end

  function ui.renderWelcome()
    local msg1 = "UltimateEdit"
    local msg2 = "Select a file from the workspace to start."
    local contentW = state.w - state.sidebarW
    local cx1 = state.sidebarW + math.floor((contentW - #msg1) / 2)
    local cx2 = state.sidebarW + math.floor((contentW - #msg2) / 2)
    local cy = math.floor(state.h / 2)
    gpu.setBackground(state.syntax.C.BG)
    gpu.fill(state.sidebarW + 1, 2, contentW, state.h - 2, " ")
    gpu.setForeground(state.syntax.C.HINT); gpu.set(cx1, cy, msg1)
    gpu.setForeground(state.syntax.C.DIM); gpu.set(cx2, cy + 2, msg2)
  end

  function ui.indentGuideLen(li, line)
    local indent = line:match("^(%s*)") or ""
    local len = unicode.len(indent)
    if line:match("%S") then return len end

    local prevLen, nextLen = 0, 0
    for i = li - 1, math.max(1, li - 20), -1 do
      local l = state.buffer[i] or ""
      if l:match("%S") then
        prevLen = unicode.len(l:match("^(%s*)") or "")
        break
      end
    end
    for i = li + 1, math.min(#state.buffer, li + 20) do
      local l = state.buffer[i] or ""
      if l:match("%S") then
        nextLen = unicode.len(l:match("^(%s*)") or "")
        break
      end
    end
    return math.max(prevLen, nextLen)
  end

  function ui.renderLine(srow, li, isCur)
    local line = state.buffer[li] or ""
    local C = state.syntax.C
    local lineBg = isCur and C.CUR_BG or C.BG
    local contentW = state.w - state.gutterW - state.sidebarW - 1
    
    ui.fillClipped(state.sidebarW + state.gutterW + 1, srow, contentW, lineBg)

    local sr1, sc1, sr2, sc2 = state.core.selNorm()
    local hasSelOnLine = sr1 ~= nil and li >= sr1 and li <= sr2
    local selA = hasSelOnLine and ((li == sr1) and sc1 or 1) or nil
    local selB = hasSelOnLine and ((li == sr2) and (sc2 - 1) or unicode.len(line)) or nil
    local findRanges = nil
    if state.showFindHighlight ~= false and state.findTerm and state.findTerm ~= "" then
      findRanges = state.core.findLineMatches(line, state.findTerm, li)
    end
    local hasFindOnLine = findRanges and #findRanges > 0
    local curFind = state.findCurrent

    local function bgAt(pos)
      if hasSelOnLine and pos >= selA and pos <= selB then return C.SEL_BG end
      if curFind and curFind.line == li and pos >= curFind.start and pos <= curFind.finish then
        return C.FIND_CUR_BG
      end
      if hasFindOnLine then
        for _, r in ipairs(findRanges) do
          if pos >= r.start and pos <= r.finish then return C.FIND_BG end
        end
      end
      return lineBg
    end

    local function drawSegment(col, text, fgCol)
      local slen = unicode.len(text)
      if col + slen <= state.scrollX or col > state.scrollX + contentW then return end
      local startC = math.max(1, state.scrollX - col + 2)
      local endC   = contentW - math.max(0, col - state.scrollX - 1)
      local sub    = unicode.sub(text, startC, endC)
      local gx     = state.sidebarW + state.gutterW + math.max(1, col - state.scrollX)
      local subLen = unicode.len(sub)
      if not hasSelOnLine and not hasFindOnLine and not (curFind and curFind.line == li) then
        ui.setClipped(gx, srow, sub, fgCol, lineBg)
        return
      end
      local absStart = col + startC - 1
      if hasSelOnLine and not hasFindOnLine and not (curFind and curFind.line == li) then
        local absEnd = absStart + subLen - 1
        if absEnd < selA or absStart > selB then
          ui.setClipped(gx, srow, sub, fgCol, lineBg)
        elseif absStart >= selA and absEnd <= selB then
          ui.setClipped(gx, srow, sub, fgCol, C.SEL_BG)
        else
          local tx, tIdx = gx, 1
          local beforeLen = math.max(0, selA - absStart)
          local midLen = math.max(0, math.min(absEnd, selB) - math.max(absStart, selA) + 1)
          if beforeLen > 0 then
            ui.setClipped(tx, srow, unicode.sub(sub, tIdx, tIdx + beforeLen - 1), fgCol, lineBg)
            tx, tIdx = tx + beforeLen, tIdx + beforeLen
          end
          if midLen > 0 then
            ui.setClipped(tx, srow, unicode.sub(sub, tIdx, tIdx + midLen - 1), fgCol, C.SEL_BG)
            tx, tIdx = tx + midLen, tIdx + midLen
          end
          if tIdx <= subLen then ui.setClipped(tx, srow, unicode.sub(sub, tIdx), fgCol, lineBg) end
        end
        return
      end

      local tx, idx = gx, 1
      while idx <= subLen do
        local bg = bgAt(absStart + idx - 1)
        local j = idx + 1
        while j <= subLen and bgAt(absStart + j - 1) == bg do j = j + 1 end
        local part = unicode.sub(sub, idx, j - 1)
        ui.setClipped(tx, srow, part, fgCol, bg)
        tx = tx + unicode.len(part)
        idx = j
      end
    end

    local function drawIndentGuides()
      local indentLen = ui.indentGuideLen(li, line)
      if indentLen < 2 then return end
      for col = 1, indentLen, 2 do
        if col > state.scrollX and col <= state.scrollX + contentW then
          local ch = unicode.sub(line, col, col)
          if not line:match("%S") or ch == " " or ch == "\t" then
            local gx = state.sidebarW + state.gutterW + (col - state.scrollX)
            local bx1, bx2 = ui.popupSpan(srow)
            if not bx1 or gx < bx1 or gx > bx2 then
              gpu.setBackground(bgAt(col))
              gpu.setForeground(C.INDENT_GUIDE)
              gpu.set(gx, srow, "│")
            end
          end
        end
      end
    end

    if state.showSyntax == false or not state.isLua then drawSegment(1, line, C.FG)
    else
      local segs = state.syntax.highlight(line)
      local col = 1
      for _, s in ipairs(segs) do drawSegment(col, s[1], s[2]); col = col + unicode.len(s[1]) end
    end
    if state.showGuides ~= false then drawIndentGuides() end
    return selA, selB
  end

  function ui.findStickyContext()
    if state.showSticky == false or not state.target or not state.isLua or state.scrollY <= 0 then
      state.stickyCount = 0
      state.stickyContext = nil
      state.stickyContextKey = nil
      return nil
    end
    local version = state.bufferVersion or 0
    if not state.stickyRanges or state.stickyRanges.key ~= (state.target or "") .. ":" .. tostring(version) then
      local stack, ranges = {}, {}
      for li, raw in ipairs(state.buffer) do
        local code = (raw or ""):gsub("%-%-.*$", "")
        local compact = code:gsub("^%s+", ""):gsub("%s+$", "")
        if compact ~= "" then
          if compact:match("^end%f[^%w_]") or compact:match("^until%f[^%w_]") then
            local opened = table.remove(stack)
            if opened and opened.kind == "function" then
              opened.finish = li
              ranges[#ranges + 1] = opened
            end
          end
          local hasInlineEnd = compact:match("%f[%w_]end%f[^%w_]") or compact:match("%f[%w_]until%f[^%w_]")
          if not hasInlineEnd then
            if compact:match("%f[%w_]function%f[^%w_]") then
              stack[#stack + 1] = {kind = "function", line = li, text = raw}
            elseif (not compact:match("^elseif%f[^%w_]")) and (compact:match("%f[%w_]then%s*$") or compact:match("%f[%w_]do%s*$") or compact:match("^repeat%f[^%w_]")) then
              stack[#stack + 1] = {kind = "block", line = li, text = raw}
            end
          end
        end
      end
      for _, opened in ipairs(stack) do
        if opened.kind == "function" then
          opened.finish = #state.buffer
          ranges[#ranges + 1] = opened
        end
      end
      table.sort(ranges, function(a, b) return a.line < b.line end)
      state.stickyRanges = {key = (state.target or "") .. ":" .. tostring(version), ranges = ranges}
    end
    local cacheKey = (state.target or "") .. ":" .. tostring(state.scrollY) .. ":" .. tostring(version)
    if state.stickyContextKey == cacheKey then return state.stickyContext end
    local topLine = state.scrollY + 1
    local found = nil
    local ranges = state.stickyRanges and state.stickyRanges.ranges or {}
    for i = #ranges, 1, -1 do
      local r = ranges[i]
      if r.line < topLine and r.finish >= topLine then
        found = {line = r.line, text = r.text}
        break
      end
    end
    state.stickyContextKey = cacheKey
    state.stickyContext = found and {found} or nil
    state.stickyCount = found and 1 or 0
    return state.stickyContext
  end

  function ui.drawStickyContext(ctxs)
    if not ctxs or #ctxs == 0 then return end
    local keyParts = {tostring(state.scrollX)}
    for _, ctx in ipairs(ctxs) do keyParts[#keyParts + 1] = tostring(ctx.line) .. ":" .. tostring(ctx.text) end
    local key = table.concat(keyParts, "|")
    if state.stickyDrawKey == key then return end
    state.stickyDrawKey = key
    local C = state.syntax.C
    local contentW = state.w - state.gutterW - state.sidebarW - 1
    local x = state.sidebarW + state.gutterW + 1
    for idx, ctx in ipairs(ctxs) do
      local y = 1 + idx
      gpu.setBackground(C.STICKY_BG)
      gpu.fill(state.sidebarW + 1, y, state.w - state.sidebarW - 1, 1, " ")
      gpu.setForeground(C.GT_CUR)
      gpu.set(state.sidebarW + 1, y, string.format("%3d ", ctx.line))

      local line = ctx.text or ""
      local function drawPart(col, text, fg)
        if text == "" then return end
        local slen = unicode.len(text)
        if col + slen <= state.scrollX or col > state.scrollX + contentW then return end
        local startC = math.max(1, state.scrollX - col + 2)
        local endC = contentW - math.max(0, col - state.scrollX - 1)
        local sub = unicode.sub(text, startC, endC)
        local gx = x + math.max(0, col - state.scrollX - 1)
        gpu.setBackground(C.STICKY_BG)
        gpu.setForeground(fg)
        gpu.set(gx, y, sub)
      end

      local col = 1
      for _, seg in ipairs(state.syntax.highlight(line)) do
        drawPart(col, seg[1], seg[2])
        col = col + unicode.len(seg[1])
      end
    end
  end

  function ui.flush(force)
    local edH = state.h - 2
    local buffered = false
    if force or state.presentFull then
      buffered = ui.beginBufferedFrame()
      if buffered then force = true end
    end
    state.presentFull = nil
    if force then
      state.menuBarKey = nil
      state.stickyDrawKey = nil
      if state.popup then state.popup.dirty = true end
    end
    local prevStickyCount = state.stickyCount or 0
    local sticky = ui.findStickyContext()
    local stickyKey = ""
    if sticky then
      local parts = {}
      for _, ctx in ipairs(sticky) do parts[#parts + 1] = tostring(ctx.line) .. ":" .. tostring(ctx.text) end
      stickyKey = table.concat(parts, "|")
    end
    if state.stickyKey ~= stickyKey then
      ui.invalidateRows(2, 1 + math.max(prevStickyCount, state.stickyCount or 0, 1))
      state.stickyKey = stickyKey
    end
    state.stickyText = stickyKey ~= "" and stickyKey or nil
    ui.renderSidebar(force)
    
    if not state.target then
      if force or not state.welcomeDrawn then ui.renderWelcome(); state.welcomeDrawn = true end
    else
      if state.welcomeDrawn then force = true; state.welcomeDrawn = false end
      if force then state.sbCache = nil end
      for i = 1, edH do
        local rowY = i + 1
        local stickyOwnsRow = ui.isStickyRow(rowY)
        if stickyOwnsRow then rowCache[i] = nil
        else
        local li    = i + state.scrollY
        local isCur = (li == state.cy)
        local txt   = state.buffer[li] or ""
        
        local sr1, sc1, sr2, sc2 = state.core.selNorm()
        local hasSelOnLine = sr1 ~= nil and li >= sr1 and li <= sr2
        local sA = hasSelOnLine and ((li == sr1) and sc1 or 1) or nil
        local sB = hasSelOnLine and ((li == sr2) and (sc2 - 1) or unicode.len(txt)) or nil
        local curCx = isCur and state.cx or nil
        local findVersion = state.findVersion or 0

        local entry = rowCache[i]
        if force or not entry or entry.li ~= li or entry.t ~= txt or entry.c ~= isCur or entry.sa ~= sA or entry.sb ~= sB or entry.cx ~= curCx or entry.sx ~= state.scrollX or entry.fv ~= findVersion then
          ui.fillClipped(state.sidebarW + 1, rowY, state.gutterW, state.syntax.C.BAR_BG)
          ui.setClipped(state.sidebarW + 1, rowY, state.buffer[li] and string.format("%3d ", li) or "    ", isCur and state.syntax.C.GT_CUR or state.syntax.C.GT_DIM, state.syntax.C.BAR_BG)
          local rSa, rSb = ui.renderLine(rowY, li, isCur)
          rowCache[i] = {li = li, t = txt, c = isCur, sa = rSa, sb = rSb, cx = curCx, sx = state.scrollX, fv = findVersion}
        end
        end
      end
      ui.renderScrollbar()
      ui.drawStickyContext(sticky)
    end

    ui.drawMenu()
    if state.menuActive then ui.drawDropdown() end
    if state.popup then ui.drawPopup() end
    if buffered then ui.endBufferedFrame() end
  end

  function ui.drawCursor()
    if not state.target then return end
    state.core.updateGhost()
    local sx = state.sidebarW + state.gutterW + (state.cx - state.scrollX)
    local sy = (state.cy - state.scrollY) + 1
    if ui.isStickyRow(sy) then return end
    if state.popup then
      local p = state.popup
      if p.focused ~= false then return end
      if sx >= p.x and sx < p.x + p.w and sy >= p.y and sy < p.y + p.h then return end
    end
    local ch = unicode.sub(state.buffer[state.cy] or "", state.cx, state.cx)
    
    if state.ghostText and ch == "" then
      gpu.setBackground(state.syntax.C.BG)
      gpu.setForeground(state.syntax.C.GT_DIM)
      gpu.set(sx, sy, state.ghostText)
    end

    gpu.setBackground(state.syntax.C.FG)
    gpu.setForeground(state.syntax.C.BG)
    gpu.set(sx, sy, ch ~= "" and ch or " ")
  end

  function ui.init()
    ui.clear(); ui.flush(true); ui.drawStatus()
  end

  return ui
end
