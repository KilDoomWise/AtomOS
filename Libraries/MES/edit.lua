return function(args, api)
  local gpu     = require("graphics")
  local fs      = require("filesystem")
  local unicode = require("unicode")
  local event   = require("event") -- Юзаем наш новый ивент-движок

  local path = args[1]
  if not path then api.print("Usage: edit <filename>"); return end

  local target = api.resolve(path)
  local buffer = {}

  if fs.exists(target) then
    if fs.isDir(target) then api.print("edit: " .. target .. " is a directory"); return end
    local data = fs.readAll(target)
    if data then
      data = data:gsub("\r", "")
      for line in (data .. "\n"):gmatch("([^\n]*)\n") do table.insert(buffer, line) end
    end
  end
  if #buffer == 0 then buffer = {""} end

  local w, h       = gpu.getResolution()
  local cx, cy     = 1, 1
  local scrollX, scrollY = 0, 0
  local running, modified = true, false
  local gutterW, findTerm = 4, ""
  local contentW, edH = w - gutterW, h - 2
  local isLua = target:match("%.lua$") ~= nil

  -- GitHub Dark Theme
  local C = {
    BG = 0x0D1117, CUR_BG = 0x161B22, FG = 0xE6EDF3, BAR_BG = 0x161B22,
    KEY = 0xFFFFFF, HINT = 0x79C0FF, DIM = 0x8B949E, OK = 0x3FB950,
    GT_DIM = 0x3D444D, GT_CUR = 0x8B949E, KW = 0xFF7B72, BUILTIN = 0xD2A8FF,
    STR = 0xA5D6FF, CMT = 0x6E7681, NUM = 0xE8B87D
  }

  local LUA_KW = {["local"]=1,["function"]=1,["return"]=1,["if"]=1,["then"]=1,["else"]=1,["end"]=1,["for"]=1,["while"]=1,["do"]=1,["and"]=1,["or"]=1,["not"]=1,["nil"]=1}
  local LUA_BI = {["require"]=1,["print"]=1,["math"]=1,["table"]=1,["string"]=1,["io"]=1,["gpu"]=1}

  local function highlight(line)
    local segs, i, len = {}, 1, #line
    while i <= len do
      local c = line:sub(i, i)
      if line:sub(i, i+1) == "--" then table.insert(segs, {line:sub(i), C.CMT}); break
      elseif c == '"' or c == "'" then
        local q, j = c, i + 1
        while j <= len and line:sub(j,j) ~= q do j = j + (line:sub(j,j) == "\\" and 2 or 1) end
        table.insert(segs, {line:sub(i, j), C.STR}); i = j + 1
      elseif c:match("%d") then
        local j = i
        while j <= len and line:sub(j,j):match("[%d%.xX]") do j = j + 1 end
        table.insert(segs, {line:sub(i, j-1), C.NUM}); i = j
      elseif c:match("[%a_]") then
        local j = i
        while j <= len and line:sub(j,j):match("[%w_]") do j = j + 1 end
        local w = line:sub(i, j-1)
        table.insert(segs, {w, LUA_KW[w] and C.KW or LUA_BI[w] and C.BUILTIN or C.FG}); i = j
      else
        local last = segs[#segs]
        if last and last[2] == C.FG then last[1] = last[1] .. c else table.insert(segs, {c, C.FG}) end
        i = i + 1
      end
    end
    return segs
  end

  local function renderLine(srow, li, isCur)
    local line = buffer[li] or ""
    gpu.setBackground(isCur and C.CUR_BG or C.BG)
    gpu.fill(gutterW + 1, srow, contentW, 1, " ")
    if #line > 0 then
      if not isLua then gpu.setForeground(C.FG); gpu.set(gutterW + 1, srow, unicode.sub(line, 1+scrollX, contentW+scrollX))
      else
        local segs, col = highlight(line), 1
        for _, s in ipairs(segs) do
          local slen = unicode.len(s[1])
          if col + slen > scrollX and col <= scrollX + contentW then
            gpu.setForeground(s[2])
            gpu.set(gutterW + math.max(1, col - scrollX), srow, unicode.sub(s[1], math.max(1, scrollX - col + 2), contentW - math.max(0, col - scrollX - 1)))
          end
          col = col + slen
        end
      end
    end
  end

  local rowCache = {}
  local function flush(force)
    if force then rowCache = {} end
    for i = 1, edH do
      local li, isCur = i + scrollY, (i + scrollY == cy)
      local txt = buffer[li] or ""
      if force or not rowCache[i] or rowCache[i].li ~= li or rowCache[i].t ~= txt or rowCache[i].c ~= isCur then
        gpu.setBackground(C.BAR_BG); gpu.setForeground(isCur and C.GT_CUR or C.GT_DIM)
        gpu.set(1, i + 1, buffer[li] and string.format("%3d ", li) or "    ")
        renderLine(i + 1, li, isCur)
        rowCache[i] = {li=li, t=txt, c=isCur}
      end
    end
  end

  local function drawStatus(msg)
    gpu.setBackground(C.BAR_BG); gpu.fill(1, h, w, 1, " ")
    if msg then gpu.setForeground(C.OK); gpu.set(2, h, msg)
    else gpu.setForeground(C.DIM); gpu.set(2, h, string.format("Ln %d/%d  Col %d %s", cy, #buffer, cx, modified and "[+]" or "")) end
  end

  local function drawMenu()
    gpu.setBackground(C.BAR_BG); gpu.fill(1, 1, w, 1, " ")
    local x, items = 2, {{"^S","Save"},{"^X","Exit"},{"^F","Find"},{"^G","Goto"}}
    for _, it in ipairs(items) do
      gpu.setForeground(C.KEY); gpu.set(x, 1, it[1]); x = x + #it[1]
      gpu.setForeground(C.HINT); gpu.set(x, 1, " "..it[2].."  ")
      x = x + #it[2] + 3
    end
  end

  local function clamp()
    if cy - scrollY > edH then scrollY = cy - edH end
    if cy - scrollY < 1 then scrollY = cy - 1 end
    if cx - scrollX > contentW then scrollX = cx - contentW end
    if cx - scrollX < 1 then scrollX = cx - 1 end
  end

  local function input(p, default)
    local s = default or ""
    drawStatus(p .. " " .. s)
    while true do
      gpu.set(2 + #p + #s + 1, h, "_")
      local e = {event.pull()}
      if e[1] == "key_down" then
        if e[4] == 28 then return s elseif e[4] == 1 then return nil
        elseif e[4] == 14 then s = s:sub(1, -2); drawStatus(p .. " " .. s)
        elseif e[3] >= 32 then s = s .. unicode.char(e[3]); drawStatus(p .. " " .. s) end
      end
    end
  end

  drawMenu(); flush(true); drawStatus()

  while running do
    local sx, sy = (cx - scrollX) + gutterW, (cy - scrollY) + 1
    gpu.setBackground(C.FG); gpu.setForeground(C.BG); gpu.set(sx, sy, unicode.sub(buffer[cy], cx, cx) ~= "" and unicode.sub(buffer[cy], cx, cx) or " ")
    
    local sig = {event.pull()}
    flush() -- Восстановит строку под курсором

    if sig[1] == "key_down" then
      local char, code, redraw = sig[3], sig[4], false
      if char == 19 then -- Save
        local f = fs.open(target, "w"); if f then fs.write(f, table.concat(buffer, "\n")); fs.close(f); modified = false; drawStatus("Saved!") end
      elseif char == 24 then running = false
      elseif char == 6 then -- Find
        local f = input("Find:", findTerm)
        if f ~= nil then
          if f ~= "" then findTerm = f end
          if findTerm ~= "" then
            local found = false
            for i = 0, #buffer - 1 do
              local li = (cy - 1 + i) % #buffer + 1
              local startCol = (i == 0) and cx + 1 or 1
              local fx = buffer[li]:find(findTerm, startCol, true)
              if fx then cy, cx, redraw = li, fx, true; found = true; break end
            end
            if not found then drawStatus("Not found: " .. findTerm) end
          end
        end
      elseif char == 7 then -- Goto
        local g = tonumber(input("Line:"))
        if g and buffer[g] then cy, cx, redraw = g, 1, true end
      elseif code == 200 then if cy > 1 then cy = cy - 1; cx = math.min(cx, #buffer[cy]+1); redraw = true end
      elseif code == 208 then if cy < #buffer then cy = cy + 1; cx = math.min(cx, #buffer[cy]+1); redraw = true end
      elseif code == 203 then if cx > 1 then cx = cx - 1 elseif cy > 1 then cy = cy - 1; cx = #buffer[cy]+1 end; redraw = true
      elseif code == 205 then if cx <= #buffer[cy] then cx = cx + 1 elseif cy < #buffer then cy = cy + 1; cx = 1 end; redraw = true
      elseif code == 199 then cx = 1; redraw = true -- Home
      elseif code == 207 then cx = #buffer[cy] + 1; redraw = true -- End
      elseif code == 201 then cy = math.max(1, cy - edH); redraw = true -- PgUp
      elseif code == 209 then cy = math.min(#buffer, cy + edH); redraw = true -- PgDn
      elseif code == 14 then -- Backspace
        if cx > 1 then buffer[cy] = buffer[cy]:sub(1, cx-2)..buffer[cy]:sub(cx); cx = cx - 1; modified, redraw = true, true
        elseif cy > 1 then local p = #buffer[cy-1]; buffer[cy-1] = buffer[cy-1]..buffer[cy]; table.remove(buffer, cy); cy, cx = cy-1, p+1; modified, redraw = true, true end
      elseif code == 28 then -- Enter
        local ind = buffer[cy]:match("^(%s*)") or ""
        table.insert(buffer, cy+1, ind..buffer[cy]:sub(cx))
        buffer[cy] = buffer[cy]:sub(1, cx-1)
        cy, cx, modified, redraw = cy+1, #ind+1, true, true
      elseif char >= 32 then
        buffer[cy] = buffer[cy]:sub(1, cx-1)..unicode.char(char)..buffer[cy]:sub(cx)
        cx, modified, redraw = cx+1, true, true
      end
      if redraw then clamp(); flush(); drawStatus() end

    elseif sig[1] == "touch" or sig[1] == "drag" then
      local tx, ty = sig[3] - gutterW, sig[4] - 1
      if ty >= 1 and ty <= edH and buffer[ty + scrollY] then
        cy = ty + scrollY
        cx = math.min(math.max(1, tx + scrollX), #buffer[cy] + 1)
        flush(); drawStatus()
      end
    elseif sig[1] == "scroll" then
      local dir = -sig[5]
      if (dir > 0 and scrollY < #buffer - edH) or (dir < 0 and scrollY > 0) then
        scrollY = scrollY + dir
        flush(true)
      end
    end
  end
  api.clear()
end