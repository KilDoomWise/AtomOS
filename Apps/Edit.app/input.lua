return function(state)
  local input = {}
  local unicode = require("unicode")
  local fs = require("filesystem")

  function input.executeMenu(mIdx, iIdx)
    if mIdx == 1 then
      if iIdx == 1 then if state.core.save() then state.statusMsg = "Saved!" end
      elseif iIdx == 2 then state.core.closeFile()
      elseif iIdx == 3 then state.running = false end
    elseif mIdx == 2 then
      if iIdx == 1 then input.showPopup("find", "Find:", state.findTerm)
      elseif iIdx == 2 then input.showPopup("replace_find", "Replace:", state.findTerm)
      elseif iIdx == 3 then input.showPopup("goto", "Go to line:", "")
      end
    end
  end

  function input.showPopup(ptype, label, text, nodePath, x, y)
    local w = math.max(30, #label + 6, #text + 8)
    local h = 5
    local px = x or (state.w - w - 2)
    local py = y or 2
    if px + w > state.w then px = state.w - w end
    if py + h > state.h then py = state.h - h end
    state.popup = {type=ptype, label=label, text=text, nodePath=nodePath, x=px, y=py, w=w, h=h}
  end

  function input.doFind()
    if state.findTerm ~= "" then
      for i = 0, #state.buffer - 1 do
        local li = (state.cy - 1 + i) % #state.buffer + 1
        local startCol = (i == 0) and state.cx + 1 or 1
        local lineStr = state.buffer[li]
        local bytePos = lineStr:find(state.findTerm, 1, true)
        if bytePos then 
          local charPos = unicode.len(lineStr:sub(1, bytePos - 1)) + 1
          if i > 0 or charPos >= startCol then
            state.cy, state.cx = li, charPos
            return true
          end
        end
      end
      state.statusMsg = "Not found: " .. state.findTerm
    end
    return false
  end

  function input.handle(sig)
    if sig[1] == "key_up" then
      local code = sig[4]
      if code == 29 or code == 157 then state.ctrlHeld  = false end
      if code == 42 or code == 54  then state.shiftHeld = false end
    end

    if sig[1] == "key_down" or sig[1] == "touch" then state.statusMsg = nil end
    if sig[1] == "key_down" or sig[1] == "touch" or sig[1] == "drag" then 
       if sig[4] ~= 14 and sig[4] ~= 211 and sig[4] ~= 28 and sig[3] and sig[3] < 32 then
          state.lastAction = ""
       end
    end

    state.ui.flush()

    if state.popup then
      if sig[1] == "scroll" then return end
      if sig[1] == "touch" then
        local tx, ty = sig[3], sig[4]
        if tx == state.popup.x + state.popup.w - 3 and ty == state.popup.y then
          state.popup = nil; state.ui.flush(true); return
        end
      elseif sig[1] == "key_down" then
        local char, code = sig[3], sig[4]
        if code == 28 then
          local val, ptype, nPath = state.popup.text, state.popup.type, state.popup.nodePath
          state.popup = nil
          if ptype == "find" then state.findTerm = val; input.doFind()
          elseif ptype == "replace_find" then
             state.findTerm = val
             if input.doFind() then input.showPopup("replace_with", "Replace with:", "") end
          elseif ptype == "replace_with" then
             state.core.pushHistory()
             local line = state.buffer[state.cy]
             state.buffer[state.cy] = unicode.sub(line, 1, state.cx - 1) .. val .. unicode.sub(line, state.cx + unicode.len(state.findTerm))
             state.cx = state.cx + unicode.len(val)
             state.modified = true
             state.lastAction = "replace"
          elseif ptype == "goto" then
             local g = tonumber(val)
             if g and state.buffer[g] then state.cy, state.cx = g, 1 end
          elseif ptype == "new" then
             if val and val ~= "" then
                local newPath = nPath == "/" and ("/" .. val) or (nPath .. "/" .. val)
                if val:sub(-1) == "/" then fs.makeDir(newPath)
                else
                  local f = fs.open(newPath, "w")
                  if f then fs.close(f) end
                  state.core.openFile(newPath)
                end
                state.expandedDirs[nPath] = true
                state.core.refreshTree()
             end
          end
          state.ui.flush(true); state.ui.drawStatus()
        elseif code == 1 or (char == 3 and state.ctrlHeld) then 
          state.popup = nil; state.ui.flush(true); state.ui.drawStatus()
        elseif code == 14 then
          state.popup.text = unicode.sub(state.popup.text, 1, -2); state.ui.flush(); state.ui.drawStatus()
        elseif char >= 32 then
          state.popup.text = state.popup.text .. unicode.char(char); state.ui.flush(); state.ui.drawStatus()
        end
      end
      return
    end

    if state.menuActive then
      if sig[1] == "scroll" then return end
      if sig[1] == "key_down" then
        local code = sig[4]
        if code == 1 then state.menuActive = nil; state.ui.flush(true)
        elseif code == 200 then state.itemIdx = math.max(1, state.itemIdx - 1); state.ui.flush(true)
        elseif code == 208 then 
          local max = #state.ui.menus[state.menuIdx].items
          state.itemIdx = math.min(max, state.itemIdx + 1); state.ui.flush(true)
        elseif code == 203 then state.menuIdx = 1; state.itemIdx = 1; state.ui.flush(true)
        elseif code == 205 then state.menuIdx = 2; state.itemIdx = 1; state.ui.flush(true)
        elseif code == 28 then
          local m, i = state.menuIdx, state.itemIdx
          state.menuActive = nil; state.ui.flush(true)
          input.executeMenu(m, i)
          state.ui.drawStatus()
        end
      elseif sig[1] == "touch" then
         local tx, ty = sig[3], sig[4]
         local m = state.ui.menus[state.menuIdx]
         local w, h = 14, #m.items + 2
         if tx >= m.x and tx < m.x + w and ty >= 2 and ty <= 2 + h then
            local clickedIdx = ty - 2
            if clickedIdx >= 1 and clickedIdx <= #m.items then
               state.menuActive = nil; state.ui.flush(true)
               input.executeMenu(state.menuIdx, clickedIdx)
               state.ui.drawStatus()
            end
         else state.menuActive = nil; state.ui.flush(true) end
      end
      return
    end

    if sig[1] == "clipboard" then
      state.core.pushHistory(); state.lastAction = "paste"
      if state.sel then state.core.selDelete() end
      local text = sig[3]:gsub("\r", "")
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

      if char == 24 then state.running = false
      elseif char == 23 then state.core.closeFile(); redraw = true end

      if state.target then
        if code == 44 and state.ctrlHeld then
           if state.core.undo() then state.statusMsg = "Undo" end; redraw = true
        elseif code == 35 and state.ctrlHeld then
           input.showPopup("replace_find", "Replace:", state.findTerm); redraw = true
        elseif code == 46 and state.ctrlHeld then 
          if state.sel then state.clipboard = state.core.getSelText(); state.statusMsg = "Copied!" end
        elseif code == 45 and state.ctrlHeld then
          if state.sel then state.core.pushHistory(); state.clipboard = state.core.getSelText(); state.core.selDelete(); redraw = true; state.statusMsg = "Cut!" end
        elseif char == 1 and state.ctrlHeld then
          if state.sel then state.sel = nil; redraw = true else state.cx = 1; state.cy = 1; redraw = true end
        elseif char == 4 and state.ctrlHeld then
          state.cx = unicode.len(state.buffer[#state.buffer]) + 1; state.cy = #state.buffer; redraw = true
        elseif char == 19 then
          if state.core.save() then state.statusMsg = "Saved!" end
        elseif char == 6 then input.showPopup("find", "Find:", state.findTerm); redraw = true
        elseif char == 7 then input.showPopup("goto", "Line:", ""); redraw = true
        elseif code == 15 then 
          state.core.pushHistory(); state.lastAction = "tab"
          if state.ghostText then
             state.buffer[state.cy] = unicode.sub(state.buffer[state.cy], 1, state.cx - 1) .. state.ghostText .. unicode.sub(state.buffer[state.cy], state.cx)
             state.cx = state.cx + unicode.len(state.ghostText)
             state.modified = true
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
        elseif code == 199 then moveHelper(true, function() state.cx = 1 end, function() end); redraw = true
        elseif code == 207 then moveHelper(true, function() state.cx = unicode.len(state.buffer[state.cy]) + 1 end, function() end); redraw = true
        elseif code == 201 then state.cy = math.max(1, state.cy - (state.h - 2)); state.sel = nil; redraw = true
        elseif code == 209 then state.cy = math.min(#state.buffer, state.cy + (state.h - 2)); state.sel = nil; redraw = true
        elseif code == 211 then
          if state.lastAction ~= "del" then state.core.pushHistory(); state.lastAction = "del" end
          if state.sel then state.core.selDelete(); redraw = true
          else
            local line = state.buffer[state.cy]
            if state.cx <= unicode.len(line) then state.buffer[state.cy] = unicode.sub(line, 1, state.cx - 1) .. unicode.sub(line, state.cx + 1); state.modified, redraw = true, true
            elseif state.cy < #state.buffer then state.buffer[state.cy] = line .. state.buffer[state.cy + 1]; table.remove(state.buffer, state.cy + 1); state.modified, redraw = true, true end
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
            state.cx = pos; state.modified, redraw = true, true
          elseif state.cx > 1 then
            state.buffer[state.cy] = unicode.sub(state.buffer[state.cy], 1, state.cx - 2) .. unicode.sub(state.buffer[state.cy], state.cx)
            state.cx = state.cx - 1; state.modified, redraw = true, true
          elseif state.cy > 1 then
            local prevLen = unicode.len(state.buffer[state.cy - 1])
            state.buffer[state.cy - 1] = state.buffer[state.cy - 1] .. state.buffer[state.cy]
            table.remove(state.buffer, state.cy)
            state.cy, state.cx = state.cy - 1, prevLen + 1; state.modified, redraw = true, true
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
          state.cy, state.cx = state.cy + 1, #ind + 1; state.modified, redraw = true, true
        elseif char >= 32 then
          if state.lastAction ~= "type" then state.core.pushHistory(); state.lastAction = "type" end
          if state.sel then state.core.selDelete() end
          state.buffer[state.cy] = unicode.sub(state.buffer[state.cy], 1, state.cx - 1) .. unicode.char(char) .. unicode.sub(state.buffer[state.cy], state.cx)
          state.cx, state.modified, redraw = state.cx + 1, true, true
        end
      end
      if redraw then if state.target then state.ui.clamp() end; state.ui.flush(); state.ui.drawStatus() end

    elseif sig[1] == "touch" then
      local tx, ty = sig[3], sig[4]
      if ty == 1 then
        if tx >= 2 and tx <= 7 then state.menuActive = true; state.menuIdx = 1; state.itemIdx = 1; state.ui.flush(true)
        elseif tx >= 8 and tx <= 13 then state.menuActive = true; state.menuIdx = 2; state.itemIdx = 1; state.ui.flush(true) end
        return
      end
      if ty > 1 and ty < state.h then
        if tx < state.sidebarW then
          local idx = ty - 1 + (state.sidebarScroll or 0)
          local node = state.visibleNodes and state.visibleNodes[idx]
          if node then
            if node.isDir and tx >= state.sidebarW - 3 then
              input.showPopup("new", "New in " .. node.name .. " (add / for dir):", "", node.path, tx + 2, ty)
              state.ui.flush(true)
            elseif node.isDir then
              state.expandedDirs[node.path] = not state.expandedDirs[node.path]; state.core.refreshTree(); state.ui.flush(true)
            else state.core.openFile(node.path); state.ui.flush(true) end
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
          state.sidebarScroll = math.max(0, math.min(maxScroll, (state.sidebarScroll or 0) + dir)); state.ui.flush(true)
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