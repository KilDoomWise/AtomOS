return function(state)
  local ui = {}
  local gpu = require("graphics")
  local unicode = require("unicode")
  
  local rowCache = {}
  local sidebarCache = {}

  ui.menus = {
    {name="File", x=2, items={"Save  ^S", "Close ^W", "Exit  ^X"}},
    {name="Edit", x=8, items={"Find    ^F", "Replace ^H", "Goto    ^G"}}
  }

  function ui.clear()
    if state.api then state.api.clear()
    else gpu.setBackground(0x000000); gpu.fill(1, 1, state.w, state.h, " ") end
  end

  function ui.drawMenu()
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
    local w, h = 14, #m.items + 2
    gpu.setBackground(state.syntax.C.BG)
    gpu.setForeground(state.syntax.C.DIM)
    gpu.set(m.x, 2, "╭" .. string.rep("─", w - 2) .. "╮")
    for i = 1, h - 2 do gpu.set(m.x, 2 + i, "│" .. string.rep(" ", w - 2) .. "│") end
    gpu.set(m.x, 2 + h - 1, "╰" .. string.rep("─", w - 2) .. "╯")
    for i, item in ipairs(m.items) do
      gpu.setBackground(state.itemIdx == i and state.syntax.C.SEL_BG or state.syntax.C.BG)
      gpu.setForeground(state.syntax.C.FG)
      gpu.set(m.x + 1, 2 + i, string.format(" %-11s", item))
    end
  end

  function ui.drawPopup()
    if not state.popup then return end
    local p = state.popup
    gpu.setBackground(state.syntax.C.BG)
    gpu.setForeground(state.syntax.C.DIM)
    gpu.set(p.x, p.y, "╭" .. string.rep("─", p.w - 2) .. "╮")
    for i = 1, p.h - 2 do gpu.set(p.x, p.y + i, "│" .. string.rep(" ", p.w - 2) .. "│") end
    gpu.set(p.x, p.y + p.h - 1, "╰" .. string.rep("─", p.w - 2) .. "╯")
    
    gpu.setForeground(0xFF5F56)
    gpu.set(p.x + p.w - 3, p.y, "●")

    gpu.setForeground(state.syntax.C.HINT)
    gpu.set(p.x + 2, p.y + 1, p.label)
    
    gpu.setBackground(state.syntax.C.CUR_BG)
    gpu.fill(p.x + 2, p.y + 3, p.w - 4, 1, " ")
    gpu.setForeground(state.syntax.C.FG)
    local txt = p.text .. "_"
    if unicode.len(txt) > p.w - 4 then txt = unicode.sub(txt, -(p.w - 4)) end
    gpu.set(p.x + 2, p.y + 3, txt)
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

  function ui.shiftEditor(dir)
    if not state.target then return end
    local edH = state.h - 2
    local sx = state.sidebarW + 1
    local cw = state.w - state.sidebarW - 1
    if math.abs(dir) < edH then
      if dir > 0 then gpu.copy(sx, 2 + dir, cw, edH - dir, 0, -dir)
      else gpu.copy(sx, 2, cw, edH + dir, 0, -dir) end
      local newCache = {}
      for i = 1, edH do
        local oldI = i + dir
        if oldI >= 1 and oldI <= edH then newCache[i] = rowCache[oldI] end
      end
      rowCache = newCache
    else rowCache = {} end
  end

  function ui.clamp()
    if not state.target then return end
    local edH = state.h - 2
    local contentW = state.w - state.gutterW - state.sidebarW - 1
    local oldY = state.scrollY
    if state.cy - state.scrollY > edH then state.scrollY = state.cy - edH end
    if state.cy - state.scrollY < 1   then state.scrollY = state.cy - 1   end
    local dy = state.scrollY - oldY
    if dy ~= 0 then ui.shiftEditor(dy) end
    if state.cx - state.scrollX > contentW then state.scrollX = state.cx - contentW end
    if state.cx - state.scrollX < 1        then state.scrollX = state.cx - 1        end
  end

  function ui.renderSidebar()
    if state.sidebarW <= 0 then return end
    local edH = state.h - 2
    for i = 1, edH do
      local idx = i + (state.sidebarScroll or 0)
      local node = state.visibleNodes and state.visibleNodes[idx]
      local isSel = node and (state.target == node.path) or false
      local isExp = node and node.isDir and state.expandedDirs[node.path] or false
      local cacheStr = node and (node.path .. tostring(isSel) .. tostring(isExp)) or "empty"
      
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
            gpu.setForeground(state.syntax.C.OK); gpu.set(state.sidebarW - 3, i + 1, "[+]")
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
    local sbCacheStr = state.scrollY .. "_" .. total
    if state.sbCache == sbCacheStr then return end
    state.sbCache = sbCacheStr
    
    gpu.setBackground(state.syntax.C.BG)
    gpu.setForeground(state.syntax.C.BAR_BG)
    gpu.fill(state.w, 2, 1, edH, "│")
    
    if total > edH then
      local thumbH = math.max(1, math.floor((edH / total) * edH))
      local maxScroll = total - edH
      local thumbY = 1 + math.floor((state.scrollY / maxScroll) * (edH - thumbH))
      gpu.setForeground(state.syntax.C.DIM)
      gpu.fill(state.w, 1 + thumbY, 1, thumbH, "█")
    end
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

  function ui.renderLine(srow, li, isCur)
    local line = state.buffer[li] or ""
    local C = state.syntax.C
    local lineBg = isCur and C.CUR_BG or C.BG
    local contentW = state.w - state.gutterW - state.sidebarW - 1
    
    gpu.setBackground(lineBg)
    gpu.fill(state.sidebarW + state.gutterW + 1, srow, contentW, 1, " ")

    local sr1, sc1, sr2, sc2 = state.core.selNorm()
    local hasSelOnLine = sr1 ~= nil and li >= sr1 and li <= sr2
    local selA = hasSelOnLine and ((li == sr1) and sc1 or 1) or nil
    local selB = hasSelOnLine and ((li == sr2) and (sc2 - 1) or unicode.len(line)) or nil

    if unicode.len(line) == 0 then return selA, selB end

    local function drawSegment(col, text, fgCol)
      local slen = unicode.len(text)
      if col + slen <= state.scrollX or col > state.scrollX + contentW then return end
      local startC = math.max(1, state.scrollX - col + 2)
      local endC   = contentW - math.max(0, col - state.scrollX - 1)
      local sub    = unicode.sub(text, startC, endC)
      local gx     = state.sidebarW + state.gutterW + math.max(1, col - state.scrollX)
      local subLen = unicode.len(sub)
      
      if not hasSelOnLine then
        gpu.setBackground(lineBg); gpu.setForeground(fgCol); gpu.set(gx, srow, sub)
        return
      end

      local absStart = col + startC - 1
      local absEnd   = absStart + subLen - 1

      if absEnd < selA or absStart > selB then
        gpu.setBackground(lineBg); gpu.setForeground(fgCol); gpu.set(gx, srow, sub)
      elseif absStart >= selA and absEnd <= selB then
        gpu.setBackground(C.SEL_BG); gpu.setForeground(fgCol); gpu.set(gx, srow, sub)
      else
        local p1_len = math.max(0, selA - absStart)
        local p2_len = math.min(absEnd, selB) - math.max(absStart, selA) + 1
        local p3_len = math.max(0, absEnd - selB)
        
        local tx, tIdx = gx, 1
        if p1_len > 0 then
          gpu.setBackground(lineBg); gpu.setForeground(fgCol)
          gpu.set(tx, srow, unicode.sub(sub, tIdx, tIdx + p1_len - 1))
          tx, tIdx = tx + p1_len, tIdx + p1_len
        end
        if p2_len > 0 then
          gpu.setBackground(C.SEL_BG); gpu.setForeground(fgCol)
          gpu.set(tx, srow, unicode.sub(sub, tIdx, tIdx + p2_len - 1))
          tx, tIdx = tx + p2_len, tIdx + p2_len
        end
        if p3_len > 0 then
          gpu.setBackground(lineBg); gpu.setForeground(fgCol)
          gpu.set(tx, srow, unicode.sub(sub, tIdx, tIdx + p3_len - 1))
        end
      end
    end

    if not state.isLua then drawSegment(1, line, C.FG)
    else
      local segs = state.syntax.highlight(line)
      local col = 1
      for _, s in ipairs(segs) do drawSegment(col, s[1], s[2]); col = col + unicode.len(s[1]) end
    end
    return selA, selB
  end

  function ui.flush(force)
    local edH = state.h - 2
    ui.renderSidebar()
    
    if not state.target then
      if force or not state.welcomeDrawn then ui.renderWelcome(); state.welcomeDrawn = true end
    else
      if state.welcomeDrawn then force = true; state.welcomeDrawn = false end
      if force then state.sbCache = nil end
      for i = 1, edH do
        local li    = i + state.scrollY
        local isCur = (li == state.cy)
        local txt   = state.buffer[li] or ""
        
        local sr1, sc1, sr2, sc2 = state.core.selNorm()
        local hasSelOnLine = sr1 ~= nil and li >= sr1 and li <= sr2
        local sA = hasSelOnLine and ((li == sr1) and sc1 or 1) or nil
        local sB = hasSelOnLine and ((li == sr2) and (sc2 - 1) or unicode.len(txt)) or nil
        local curCx = isCur and state.cx or nil

        local entry = rowCache[i]
        if force or not entry or entry.li ~= li or entry.t ~= txt or entry.c ~= isCur or entry.sa ~= sA or entry.sb ~= sB or entry.cx ~= curCx then
          gpu.setBackground(state.syntax.C.BAR_BG)
          gpu.setForeground(isCur and state.syntax.C.GT_CUR or state.syntax.C.GT_DIM)
          gpu.set(state.sidebarW + 1, i + 1, state.buffer[li] and string.format("%3d ", li) or "    ")
          local rSa, rSb = ui.renderLine(i + 1, li, isCur)
          rowCache[i] = {li = li, t = txt, c = isCur, sa = rSa, sb = rSb, cx = curCx}
        end
      end
      ui.renderScrollbar()
    end

    ui.drawMenu()
    if state.menuActive then ui.drawDropdown() end
    if state.popup then ui.drawPopup() end
  end

  function ui.drawCursor()
    if not state.target then return end
    state.core.updateGhost()
    local sx = state.sidebarW + state.gutterW + (state.cx - state.scrollX)
    local sy = (state.cy - state.scrollY) + 1
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