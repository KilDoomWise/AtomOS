return function(state)
  local input = {}
  local unicode = require("unicode")
  local fs = require("filesystem")

  function input.executeMenu(mIdx, iIdx)
    if mIdx == 1 then
      if iIdx == 1 then
        if state.core.save() then state.statusMsg = "Saved!" end
        state.ui.invalidateSidebar()
        state.ui.flush()
      elseif iIdx == 2 then state.core.closeFile(); state.ui.flush(true)
      elseif iIdx == 3 then state.running = false end
    elseif mIdx == 2 then
      if iIdx == 1 then input.togglePopup("find", "Find:", state.findTerm)
      elseif iIdx == 2 then input.togglePopup("replace")
      elseif iIdx == 3 then input.togglePopup("goto", "Go to line:", "")
      end
    elseif mIdx == 3 then
      if iIdx == 1 then state.showSticky = not state.showSticky
      elseif iIdx == 2 then state.showGuides = not state.showGuides
      elseif iIdx == 3 then state.showFindHighlight = not state.showFindHighlight
      elseif iIdx == 4 then state.showSyntax = not state.showSyntax
      elseif iIdx == 5 then state.showScrollMarks = not state.showScrollMarks
      end
      state.core.bumpFindVersion(true)
      state.ui.invalidateEditor()
      state.core.saveSettings()
    end
  end

  function input.showPopup(ptype, label, text, nodePath, x, y)
    if ptype == "replace" then return input.showReplacePopup(x, y) end
    local w = ptype == "find" and 46 or ptype == "quickopen" and math.min(58, math.max(38, state.w - state.sidebarW - 8)) or math.max(30, #label + 6, #text + 8)
    if ptype == "find" then w = math.min(w, math.max(34, state.w - state.sidebarW - 4)) end
    local h = ptype == "find" and 3 or ptype == "quickopen" and 9 or 5
    local px = x or (ptype == "find" and (state.w - w) or ptype == "quickopen" and (state.sidebarW + math.floor((state.w - state.sidebarW - w) / 2)) or (state.w - w - 2))
    local py = y or 2
    if px + w > state.w then px = state.w - w end
    if py + h > state.h then py = state.h - h end
    state.popup = {type=ptype, label=label, text=text, nodePath=nodePath, x=px, y=py, w=w, h=h, focused=true}
  end

  function input.showReplacePopup(x, y)
    local findText = state.findTerm or ""
    local replaceText = state.replaceTerm or ""
    local w = math.max(52, #findText + 26, #replaceText + 26)
    w = math.min(w, math.max(38, state.w - state.sidebarW - 4))
    local h = 4
    local px = x or (state.w - w - 2)
    local py = y or 2
    if px + w > state.w then px = state.w - w end
    if py + h > state.h then py = state.h - h end
    state.popup = {
      type = "replace", x = px, y = py, w = w, h = h, active = 1, focused = true,
      fields = {
        {label = "Find", text = findText},
        {label = "Replace", text = replaceText}
      },
      replaced = 0, total = nil, nextLine = 1, nextCol = 1, lastFind = findText
    }
  end

  function input.closePopup()
    local p = state.popup
    state.popup = nil
    if p then state.ui.invalidateRows(p.y, p.y + p.h - 1) end
    if p and p.type == "find" then state.core.clearFind() end
    state.ui.invalidateLine(state.cy)
    state.ui.flush()
    state.ui.drawStatus()
  end

  function input.togglePopup(ptype, label, text)
    if state.popup and state.popup.type == ptype then
      input.closePopup()
      return false
    end
    local old = state.popup
    if old then state.ui.invalidateRows(old.y, old.y + old.h - 1) end
    state.ui.invalidateLine(state.cy)
    if ptype == "replace" then input.showReplacePopup()
    else input.showPopup(ptype, label, text) end
    if state.popup then state.ui.invalidateRows(state.popup.y, state.popup.y + state.popup.h - 1) end
    state.ui.flush()
    state.ui.drawStatus()
    return true
  end

  function input.openQuickMatch(p)
    local matches = p.matches or state.core.quickMatches(p.text or "")
    if #matches == 0 then return false end
    local idx = math.max(1, math.min(p.active or 1, #matches))
    local match = matches[idx]
    local old = state.popup
    state.popup = nil
    if old then state.ui.invalidateRows(old.y, old.y + old.h - 1) end
    state.core.openFile(match.path)
    state.ui.invalidateEditor()
    state.ui.flush()
    state.ui.drawStatus()
    return true
  end

  function input.invalidateMenu(idx)
    local m = state.ui.menus[idx]
    if not m then return end
    state.ui.invalidateRows(2, 1 + #state.ui.menuItems(idx))
    state.stickyDrawKey = nil
    state.menuBarKey = nil
  end

  function input.closeMenu()
    local idx = state.menuIdx
    state.menuActive = nil
    input.invalidateMenu(idx)
    state.menuBarKey = nil
    state.ui.invalidateRows(2, 1 + (state.stickyCount or 1))
    state.ui.flush()
  end

  function input.openMenu(idx)
    if state.menuActive then input.invalidateMenu(state.menuIdx) end
    state.menuActive = true
    state.menuIdx = idx
    state.itemIdx = 1
    state.menuBarKey = nil
    state.stickyDrawKey = nil
    state.ui.flush()
  end

  function input.gotoMatch(match, center)
    if not match then return false end
    state.cy, state.cx = match.line, match.start
    state.sel = nil
    state.core.setFindCurrent(match)
    if center == false then state.ui.clamp() else state.ui.centerCursor(true) end
    return true
  end

  function input.pickMatch(matches, line, col)
    for i, match in ipairs(matches) do
      if match.line > line or (match.line == line and match.start >= col) then
        return i, match
      end
    end
    if #matches > 0 then return 1, matches[1] end
    return nil, nil
  end

  function input.pickPreviousMatch(matches, line, col)
    for i = #matches, 1, -1 do
      local match = matches[i]
      if match.line < line or (match.line == line and match.start < col) then
        return i, match
      end
    end
    if #matches > 0 then return #matches, matches[#matches] end
    return nil, nil
  end

  function input.currentFindIndex(matches)
    local cur = state.findCurrent
    if not cur then return nil end
    for i, match in ipairs(matches) do
      if match.line == cur.line and match.start == cur.start and match.finish == cur.finish then
        return i
      end
    end
    return nil
  end

  function input.doFind(term, direction)
    term = term or state.findTerm or ""
    state.core.setFindTerm(term)
    if term == "" then
      state.core.setFindCurrent(nil)
      state.findIndex, state.findTotal = 0, 0
      state.statusMsg = "Find is empty"
      return false
    end

    local matches = state.core.findMatches(term)
    state.findTotal = #matches
    if #matches == 0 then
      state.core.setFindCurrent(nil)
      state.findIndex = 0
      state.statusMsg = "Not found: " .. term
      return false
    end

    local idx, match
    local curIdx = state.findIndex
    if not curIdx or curIdx < 1 or curIdx > #matches then curIdx = input.currentFindIndex(matches) end
    if direction == -1 then
      if curIdx then idx = curIdx - 1; if idx < 1 then idx = #matches end; match = matches[idx]
      else idx, match = input.pickPreviousMatch(matches, state.cy, state.cx) end
    elseif direction == 1 then
      if curIdx then idx = curIdx + 1; if idx > #matches then idx = 1 end; match = matches[idx]
      else idx, match = input.pickMatch(matches, state.cy, state.cx) end
    else
      idx, match = input.pickMatch(matches, state.cy, state.cx)
    end

    state.findIndex = idx or 0
    input.gotoMatch(match)
    state.statusMsg = string.format("%d/%d", idx, #matches)
    return true
  end

  function input.resetReplaceProgress(p)
    p.replaced, p.total = 0, nil
    p.nextLine, p.nextCol = 1, 1
    p.lastFind = p.fields[1].text or ""
    state.replaceCount = 0
  end

  function input.replaceOne(p)
    local findText = p.fields[1].text or ""
    local replaceText = p.fields[2].text or ""
    state.replaceTerm = replaceText
    state.core.setFindTerm(findText)
    if findText == "" then
      state.statusMsg = "Find is empty"
      return false
    end

    if p.lastFind ~= findText then input.resetReplaceProgress(p) end
    local matches = state.core.findMatches(findText)
    if p.total == nil then p.total = #matches end
    if #matches == 0 then
      state.core.setFindCurrent(nil)
      state.statusMsg = "Not found: " .. findText
      return false
    end

    local picked = nil
    for _, match in ipairs(matches) do
      if match.line > p.nextLine or (match.line == p.nextLine and match.start >= p.nextCol) then
        picked = match
        break
      end
    end
    if not picked then
      state.statusMsg = string.format("Replace done %d/%d", p.replaced or 0, p.total or 0)
      return false
    end

    state.core.pushHistory()
    local line = state.buffer[picked.line]
    state.buffer[picked.line] =
      unicode.sub(line, 1, picked.start - 1) .. replaceText .. unicode.sub(line, picked.finish + 1)
    state.cy = picked.line
    state.cx = picked.start + unicode.len(replaceText)
    state.sel = nil
    state.modified = true
    state.lastAction = "replace"
    state.core.bumpFindVersion()
    state.core.setFindCurrent(nil)

    p.replaced = (p.replaced or 0) + 1
    state.replaceCount = p.replaced
    p.nextLine = picked.line
    p.nextCol = picked.start + unicode.len(replaceText)
    state.ui.centerCursor(true)
    state.statusMsg = string.format("Replace %d/%d", p.replaced, p.total or 0)
    return true
  end

  function input.copySelectionOrLine()
    if state.sel then
      state.clipboard = state.core.getSelText()
      state.statusMsg = "Copied!"
    else
      state.clipboard = (state.buffer[state.cy] or "") .. "\n"
      state.statusMsg = "Line copied"
    end
  end

  function input.cutSelectionOrLine()
    state.core.pushHistory()
    if state.sel then
      state.clipboard = state.core.getSelText()
      state.core.selDelete()
      state.statusMsg = "Cut!"
    else
      state.clipboard = state.core.cutCurrentLine()
      state.statusMsg = "Line cut"
    end
    return true
  end

  function input.pasteClipboard()
    if not state.clipboard or state.clipboard == "" then return false end
    state.core.pushHistory()
    state.lastAction = "paste"
    state.core.insertText(state.clipboard)
    state.statusMsg = "Pasted"
    return true
  end

  function input.handlePopup(sig)
    local p = state.popup
    if not p then return false end

    if sig[1] == "touch" then
      local tx, ty = sig[3], sig[4]
      local inside = tx >= p.x and tx < p.x + p.w and ty >= p.y and ty < p.y + p.h
      if not inside then
        p.focused = false
        state.ui.flush()
        return false
      end
      p.focused = true
      if p.type == "quickopen" then
        local row = ty - p.y
        if row >= 1 and row <= p.h - 1 and p.matches and p.matches[row] then
          p.active = row
          input.openQuickMatch(p)
          return true
        end
        state.ui.flush()
        return true
      end
      if p.type == "find" or p.type == "replace" then
        local prevX = p.prevX or (p.x + p.w - 8)
        local nextX = p.nextX or (p.x + p.w - 5)
        if ty == p.y + 1 and tx >= prevX and tx < prevX + 2 then
          local term = p.type == "replace" and (p.fields[1].text or "") or (p.text or "")
          input.doFind(term, -1); state.ui.flush(); state.ui.drawStatus(); return true
        elseif ty == p.y + 1 and tx >= nextX and tx < nextX + 2 then
          local term = p.type == "replace" and (p.fields[1].text or "") or (p.text or "")
          input.doFind(term, 1); state.ui.flush(); state.ui.drawStatus(); return true
        elseif ty == p.y + 1 then
          state.ui.flush(); return true
        end
      end
      if p.fields then
        if p.type == "replace" then
          if ty == p.findInputY then p.active = 1; state.ui.flush(); return true end
          if ty == p.replInputY then p.active = 2; state.ui.flush(); return true end
        else
          for i = 1, #p.fields do
            local inputY = p.y + (i - 1) * 2 + 2
            if ty == inputY then p.active = i; state.ui.flush(); return true end
          end
        end
      end
      state.ui.flush()
      return true
    end

    if sig[1] ~= "key_down" then return false end
    local char, code = sig[3], sig[4]
    if char == 6 then input.togglePopup("find", "Find:", state.findTerm); return true
    elseif code == 35 and (state.ctrlHeld or char == 8) then input.togglePopup("replace"); return true
    elseif char == 7 then input.togglePopup("goto", "Go to line:", ""); return true
    elseif char == 16 then input.togglePopup("quickopen", "Open file:", ""); return true
    end
    if code == 1 then input.closePopup(); return true end

    if not p.focused then return false end

    if code == 28 then
      if p.type == "find" then
        local changed = (p.text or "") ~= state.findTerm
        input.doFind(p.text or "", changed and 0 or 1)
        state.ui.flush(); state.ui.drawStatus()
      elseif p.type == "quickopen" then
        input.openQuickMatch(p)
      elseif p.type == "replace" then
        input.replaceOne(p)
        state.ui.flush(); state.ui.drawStatus()
      else
        local val, ptype, nPath = p.text, p.type, p.nodePath
        state.popup = nil
        if ptype == "goto" then
           local g = tonumber(val)
           if g and state.buffer[g] then state.cy, state.cx = g, 1; state.sel = nil; state.ui.centerCursor(true) end
        elseif ptype == "new" then
           if val and val ~= "" then
              local newPath = nPath == "/" and ("/" .. val) or (nPath .. "/" .. val)
              if val:sub(-1) == "/" then fs.makeDir(newPath)
              else
                local f = fs.open(newPath, "w")
                if f then fs.close(f) end
                state.core.openFile(newPath)
                state.ui.invalidateEditor()
              end
              state.expandedDirs[nPath] = true
              state.core.refreshTree()
              state.ui.invalidateSidebar()
           end
        end
        state.ui.invalidateRows(p.y, p.y + p.h - 1)
        state.ui.flush(); state.ui.drawStatus()
      end
    elseif char == 3 then
      input.closePopup()
    elseif p.type == "quickopen" and code == 200 then
      local matches = p.matches or state.core.quickMatches(p.text or "")
      p.active = math.max(1, (p.active or 1) - 1)
      if p.active > #matches then p.active = #matches end
      state.ui.flush(); state.ui.drawStatus()
    elseif p.type == "quickopen" and code == 208 then
      local matches = p.matches or state.core.quickMatches(p.text or "")
      p.active = math.min(#matches, (p.active or 1) + 1)
      state.ui.flush(); state.ui.drawStatus()
    elseif (p.type == "find" or p.type == "replace") and (code == 205 or code == 208) then
      input.doFind(p.type == "replace" and (p.fields[1].text or "") or (p.text or ""), 1)
      state.ui.flush(); state.ui.drawStatus()
    elseif (p.type == "find" or p.type == "replace") and (code == 203 or code == 200) then
      input.doFind(p.type == "replace" and (p.fields[1].text or "") or (p.text or ""), -1)
      state.ui.flush(); state.ui.drawStatus()
    elseif p.fields and code == 15 then
      p.active = p.active == 1 and 2 or 1
      state.ui.flush(); state.ui.drawStatus()
    elseif p.fields and (code == 200 or code == 208) then
      p.active = code == 200 and math.max(1, p.active - 1) or math.min(#p.fields, p.active + 1)
      state.ui.flush(); state.ui.drawStatus()
    elseif code == 14 then
      if p.fields then
        local field = p.fields[p.active]
        field.text = unicode.sub(field.text or "", 1, -2)
        if p.type == "replace" and p.active == 1 then input.resetReplaceProgress(p) end
      else
        p.text = unicode.sub(p.text or "", 1, -2)
      end
      state.ui.flush(); state.ui.drawStatus()
    elseif (char or 0) >= 32 then
      if p.fields then
        local field = p.fields[p.active]
        field.text = (field.text or "") .. unicode.char(char)
        if p.type == "replace" and p.active == 1 then input.resetReplaceProgress(p) end
      else
        p.text = (p.text or "") .. unicode.char(char)
      end
      state.ui.flush(); state.ui.drawStatus()
    end
    return true
  end

  function input.handle(sig)
    if sig[1] == "key_up" then
      local code = sig[4]
      if code == 29 or code == 157 then state.ctrlHeld  = false end
      if code == 42 or code == 54  then state.shiftHeld = false end
    end
    if sig[1] == "key_down" then
      local code = sig[4]
      if code == 29 or code == 157 then state.ctrlHeld  = true end
      if code == 42 or code == 54  then state.shiftHeld = true end
    end

    if sig[1] == "key_down" or sig[1] == "touch" then state.statusMsg = nil end
    if sig[1] == "key_down" or sig[1] == "touch" or sig[1] == "drag" then 
       if sig[4] ~= 14 and sig[4] ~= 211 and sig[4] ~= 28 and sig[3] and sig[3] < 32 then
          state.lastAction = ""
       end
    end

    if state.popup and input.handlePopup(sig) then return end

    if state.menuActive then
      if sig[1] == "scroll" then return end
      if sig[1] == "key_down" then
        local code = sig[4]
        if code == 1 then input.closeMenu()
        elseif code == 200 then state.itemIdx = math.max(1, state.itemIdx - 1); state.ui.flush()
        elseif code == 208 then 
          local max = #state.ui.menuItems(state.menuIdx)
          state.itemIdx = math.min(max, state.itemIdx + 1); state.ui.flush()
        elseif code == 203 then input.openMenu(math.max(1, state.menuIdx - 1))
        elseif code == 205 then input.openMenu(math.min(#state.ui.menus, state.menuIdx + 1))
        elseif code == 28 then
          local m, i = state.menuIdx, state.itemIdx
          input.closeMenu()
          input.executeMenu(m, i)
          state.ui.drawStatus()
        end
      elseif sig[1] == "touch" then
         local tx, ty = sig[3], sig[4]
         if ty == 1 then
            local idx = state.ui.menuAt(tx)
            if idx then
              if state.menuIdx == idx then input.closeMenu() else input.openMenu(idx) end
            else input.closeMenu() end
            return
         end
         local m = state.ui.menus[state.menuIdx]
         local w, h = state.ui.menuWidth(state.menuIdx), #state.ui.menuItems(state.menuIdx)
         if tx >= m.x and tx < m.x + w and ty >= 2 and ty <= 1 + h then
            local clickedIdx = ty - 1
            if clickedIdx >= 1 and clickedIdx <= #state.ui.menuItems(state.menuIdx) then
               local menuIdx = state.menuIdx
               input.closeMenu()
               input.executeMenu(menuIdx, clickedIdx)
               state.ui.drawStatus()
            end
         else input.closeMenu() end
      end
      return
    end

    if sig[1] == "clipboard" then
      state.core.pushHistory(); state.lastAction = "paste"
      state.core.insertText(sig[3])
      state.ui.clamp(); state.ui.flush(); state.ui.drawStatus()
      return
    end

    if sig[1] == "key_down" then
      local char, code, redraw = sig[3], sig[4], false
      if code == 29 or code == 157 then state.ctrlHeld  = true end
      if code == 42 or code == 54  then state.shiftHeld = true end

      local function moveHelper(selUpdate, cxUpdate, cyUpdate)
        if state.shiftHeld then
          if not state.sel then state.sel = {state.cy, state.cx, state.cy, state.cx} end
          cxUpdate(); cyUpdate(); state.sel[3], state.sel[4] = state.cy, state.cx
        else state.sel = nil; cxUpdate(); cyUpdate() end
      end

      if char == 17 then state.running = false
      elseif char == 23 then state.core.closeFile(); redraw = true end
      if char == 16 then input.togglePopup("quickopen", "Open file:", ""); return end

      if state.target then
        if (code == 44 and state.ctrlHeld) or char == 26 then
           if state.core.undo() then state.statusMsg = "Undo" end; redraw = true
        elseif char == 25 then
           if state.core.redo() then state.statusMsg = "Redo" end; redraw = true
        elseif code == 35 and (state.ctrlHeld or char == 8) then
           input.togglePopup("replace")
        elseif (code == 46 and state.ctrlHeld) or char == 3 then 
          input.copySelectionOrLine(); redraw = true
        elseif (code == 45 and state.ctrlHeld) or char == 24 then
          redraw = input.cutSelectionOrLine()
        elseif char == 22 then
          redraw = input.pasteClipboard()
        elseif char == 1 then
          state.core.selectAll(); redraw = true
        elseif char == 19 then
          if state.core.save() then state.statusMsg = "Saved!" end; redraw = true
        elseif char == 6 then input.togglePopup("find", "Find:", state.findTerm)
        elseif char == 7 then input.togglePopup("goto", "Go to line:", "")
        elseif code == 15 then 
          state.core.pushHistory(); state.lastAction = "tab"
          if state.ghostText then
             state.buffer[state.cy] = unicode.sub(state.buffer[state.cy], 1, state.cx - 1) .. state.ghostText .. unicode.sub(state.buffer[state.cy], state.cx)
             state.cx = state.cx + unicode.len(state.ghostText)
             state.modified = true
             state.core.bumpFindVersion()
          else state.core.insertTab() end
          redraw = true
        elseif code == 200 then moveHelper(true, function() state.cx = math.min(state.cx, unicode.len(state.buffer[math.max(1, state.cy - 1)]) + 1) end, function() state.cy = math.max(1, state.cy - 1) end); redraw = true
        elseif code == 208 then moveHelper(true, function() state.cx = math.min(state.cx, unicode.len(state.buffer[math.min(#state.buffer, state.cy + 1)]) + 1) end, function() state.cy = math.min(#state.buffer, state.cy + 1) end); redraw = true
        elseif code == 203 then
          local function moveLeft()
            if state.cx > 1 then state.cx = state.cx - 1 elseif state.cy > 1 then state.cy = state.cy - 1; state.cx = unicode.len(state.buffer[state.cy]) + 1 end
          end
          if state.ctrlHeld then
            local line = state.buffer[state.cy]
            local pos = state.cx - 1
            while pos > 1 and unicode.sub(line, pos, pos):match("%s") do pos = pos - 1 end
            while pos > 1 and not unicode.sub(line, pos - 1, pos - 1):match("%s") do pos = pos - 1 end
            if state.shiftHeld then if not state.sel then state.sel = {state.cy, state.cx, state.cy, state.cx} end; state.cx = pos; state.sel[3], state.sel[4] = state.cy, state.cx else state.sel = nil; state.cx = pos end
          else moveHelper(true, function() end, moveLeft) end
          redraw = true
        elseif code == 205 then
          local function moveRight()
            if state.cx <= unicode.len(state.buffer[state.cy]) then state.cx = state.cx + 1 elseif state.cy < #state.buffer then state.cy = state.cy + 1; state.cx = 1 end
          end
          if state.ctrlHeld then
            local line = state.buffer[state.cy]
            local len  = unicode.len(line)
            local pos  = state.cx
            while pos <= len and not unicode.sub(line, pos, pos):match("%s") do pos = pos + 1 end
            while pos <= len and unicode.sub(line, pos, pos):match("%s") do pos = pos + 1 end
            if state.shiftHeld then if not state.sel then state.sel = {state.cy, state.cx, state.cy, state.cx} end; state.cx = pos; state.sel[3], state.sel[4] = state.cy, state.cx else state.sel = nil; state.cx = pos end
          else moveHelper(true, function() end, moveRight) end
          redraw = true
        elseif code == 199 then
          if state.ctrlHeld then moveHelper(true, function() state.cy, state.cx = 1, 1 end, function() end)
          else moveHelper(true, function() state.cx = 1 end, function() end) end
          redraw = true
        elseif code == 207 then
          if state.ctrlHeld then
            moveHelper(true, function() state.cy = #state.buffer; state.cx = unicode.len(state.buffer[state.cy]) + 1 end, function() end)
          else moveHelper(true, function() state.cx = unicode.len(state.buffer[state.cy]) + 1 end, function() end) end
          redraw = true
        elseif code == 201 then state.cy = math.max(1, state.cy - (state.h - 2)); state.sel = nil; redraw = true
        elseif code == 209 then state.cy = math.min(#state.buffer, state.cy + (state.h - 2)); state.sel = nil; redraw = true
        elseif code == 211 then
          if state.lastAction ~= "del" then state.core.pushHistory(); state.lastAction = "del" end
          if state.sel then state.core.selDelete(); redraw = true
          else
            local line = state.buffer[state.cy]
            if state.cx <= unicode.len(line) then state.buffer[state.cy] = unicode.sub(line, 1, state.cx - 1) .. unicode.sub(line, state.cx + 1); state.modified, redraw = true, true; state.core.bumpFindVersion()
            elseif state.cy < #state.buffer then state.buffer[state.cy] = line .. state.buffer[state.cy + 1]; table.remove(state.buffer, state.cy + 1); state.modified, redraw = true, true; state.core.bumpFindVersion() end
          end
        elseif code == 14 then
          if state.lastAction ~= "bs" then state.core.pushHistory(); state.lastAction = "bs" end
          if state.sel then state.core.selDelete(); redraw = true
          elseif state.ctrlHeld then
            local line = state.buffer[state.cy]
            local pos = state.cx - 1
            while pos > 1 and unicode.sub(line, pos, pos):match("%s") do pos = pos - 1 end
            while pos > 1 and not unicode.sub(line, pos - 1, pos - 1):match("%s") do pos = pos - 1 end
            state.buffer[state.cy] = unicode.sub(line, 1, pos - 1) .. unicode.sub(line, state.cx)
            state.cx = pos; state.modified, redraw = true, true; state.core.bumpFindVersion()
          elseif state.cx > 1 then
            state.buffer[state.cy] = unicode.sub(state.buffer[state.cy], 1, state.cx - 2) .. unicode.sub(state.buffer[state.cy], state.cx)
            state.cx = state.cx - 1; state.modified, redraw = true, true; state.core.bumpFindVersion()
          elseif state.cy > 1 then
            local prevLen = unicode.len(state.buffer[state.cy - 1])
            state.buffer[state.cy - 1] = state.buffer[state.cy - 1] .. state.buffer[state.cy]
            table.remove(state.buffer, state.cy)
            state.cy, state.cx = state.cy - 1, prevLen + 1; state.modified, redraw = true, true; state.core.bumpFindVersion()
          end
        elseif code == 28 then
          state.core.pushHistory(); state.lastAction = "enter"
          if state.sel then state.core.selDelete() end
          local prevLine = unicode.sub(state.buffer[state.cy], 1, state.cx - 1)
          local ind = prevLine:match("^(%s*)") or ""
          if state.isLua and (prevLine:match("%s*then%s*$") or prevLine:match("%s*do%s*$") or prevLine:match("function.*%)%s*$") or prevLine:match("%{$")) then
            ind = ind .. "  "
          end
          table.insert(state.buffer, state.cy + 1, ind .. unicode.sub(state.buffer[state.cy], state.cx))
          state.buffer[state.cy] = prevLine
          state.cy, state.cx = state.cy + 1, #ind + 1; state.modified, redraw = true, true; state.core.bumpFindVersion()
        elseif (char or 0) >= 32 then
          local typed = unicode.char(char)
          local pairs = {["("] = ")", ["["] = "]", ["{"] = "}", ['"'] = '"', ["'"] = "'"}
          local line = state.buffer[state.cy]
          local nextCh = unicode.sub(line, state.cx, state.cx)
          if not state.sel and (typed == ")" or typed == "]" or typed == "}" or typed == '"' or typed == "'") and nextCh == typed then
            state.cx = state.cx + 1
            redraw = true
          else
            if state.lastAction ~= "type" then state.core.pushHistory(); state.lastAction = "type" end
            local close = pairs[typed]
            if close then
              if state.sel then
                local selected = state.core.getSelText()
                state.core.selDelete()
                state.core.insertText(typed .. selected .. close)
              else
                state.buffer[state.cy] = unicode.sub(line, 1, state.cx - 1) .. typed .. close .. unicode.sub(line, state.cx)
                state.cx = state.cx + 1
                state.modified = true
                state.core.bumpFindVersion()
              end
            else
              if state.sel then state.core.selDelete() end
              state.buffer[state.cy] = unicode.sub(state.buffer[state.cy], 1, state.cx - 1) .. typed .. unicode.sub(state.buffer[state.cy], state.cx)
              state.cx, state.modified = state.cx + 1, true
              state.core.bumpFindVersion()
            end
            redraw = true
          end
        end
      end
      if redraw then if state.target then state.ui.clamp() end; state.ui.flush(); state.ui.drawStatus() end

    elseif sig[1] == "touch" then
      local tx, ty = sig[3], sig[4]
      if ty == 1 then
        local idx = state.ui.menuAt(tx)
        if idx then input.openMenu(idx) end
        return
      end
      if ty > 1 and ty < state.h then
        if tx < state.sidebarW then
          local idx = ty - 1 + (state.sidebarScroll or 0)
          local node = state.visibleNodes and state.visibleNodes[idx]
          if node then
            if node.isDir and tx >= state.sidebarW - 3 then
              if state.popup and state.popup.type == "new" and state.popup.nodePath == node.path then
                input.closePopup()
              else
                local old = state.popup
                if old then state.ui.invalidateRows(old.y, old.y + old.h - 1) end
                input.showPopup("new", "New in " .. node.name .. " (add / for dir):", "", node.path, tx + 2, ty)
                state.ui.flush()
              end
            elseif node.isDir then
              state.expandedDirs[node.path] = not state.expandedDirs[node.path]; state.core.refreshTree(); state.ui.invalidateSidebar(); state.ui.flush()
            elseif state.target ~= node.path then
              state.core.openFile(node.path); state.ui.invalidateEditor(); state.ui.flush()
            else
              state.ui.invalidateSidebar(); state.ui.flush()
            end
          end
        elseif state.target then
          local edX = tx - state.sidebarW - state.gutterW
          local edY = ty - 1
          if state.buffer[edY + state.scrollY] then
            state.cy = edY + state.scrollY
            state.cx = math.min(math.max(1, edX + state.scrollX), unicode.len(state.buffer[state.cy]) + 1)
            state.sel = nil; state.ui.flush(); state.ui.drawStatus()
          end
        end
      end

    elseif sig[1] == "drag" then
      local tx = sig[3] - state.sidebarW - state.gutterW
      local ty = sig[4] - 1
      if state.target and tx > -state.gutterW and ty >= 1 and ty <= (state.h - 2) and state.buffer[ty + state.scrollY] then
        if not state.sel then state.sel = {state.cy, state.cx, state.cy, state.cx} end
        local dr = ty + state.scrollY
        local dc = math.min(math.max(1, tx + state.scrollX), unicode.len(state.buffer[dr]) + 1)
        state.sel[3], state.sel[4] = dr, dc
        state.cy, state.cx = dr, dc
        state.ui.clamp(); state.ui.flush(); state.ui.drawStatus()
      end

    elseif sig[1] == "scroll" then
      local dir, tx = -sig[5] * 3, sig[3]
      if tx < state.sidebarW then
        if state.visibleNodes then
          local maxScroll = math.max(0, #state.visibleNodes - (state.h - 2))
          state.sidebarScroll = math.max(0, math.min(maxScroll, (state.sidebarScroll or 0) + dir)); state.ui.invalidateSidebar(); state.ui.flush()
        end
      elseif state.target then
        local edH = state.h - 2
        local maxScroll = math.max(0, #state.buffer - edH)
        local targetY = math.max(0, math.min(maxScroll, state.scrollY + dir))
        local actualDir = targetY - state.scrollY
        if actualDir ~= 0 then
          state.scrollY = targetY
          state.ui.shiftEditor(actualDir)
          state.ui.flush()
        end
      end
    end
  end

  return input
end
