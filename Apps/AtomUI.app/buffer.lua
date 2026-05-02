return function(state)
  local gpu = require("graphics")
  local unicode = require("unicode")
  local C = state.theme.color

  local screen = {
    w = 0,
    h = 0,
    back = {},
    front = {},
    dirty = {},
    dirtyRows = {},
    clip = nil,
    cachedFg = nil,
    cachedBg = nil,
    hasDirty = false
  }

  local function cell(ch, fg, bg)
    return {ch = ch or " ", fg = fg or C.text, bg = bg or C.bg}
  end

  function screen.resize(w, h)
    screen.w, screen.h = w, h
    screen.back, screen.front, screen.dirty, screen.dirtyRows = {}, {}, {}, {}
    screen.clip = {x = 1, y = 1, w = w, h = h}
    screen.cachedFg, screen.cachedBg = nil, nil
    screen.hasDirty = true

    for y = 1, h do
      screen.back[y], screen.front[y], screen.dirty[y] = {}, {}, {}
      for x = 1, w do
        screen.back[y][x] = cell(" ", C.text, C.bg)
        screen.front[y][x] = cell("", -1, -1)
        screen.dirty[y][x] = true
      end
      screen.dirtyRows[y] = true
    end
  end

  local function insideClip(x, y)
    local c = screen.clip
    return x >= c.x and y >= c.y and x < c.x + c.w and y < c.y + c.h
  end

  local function intersect(a, b)
    local x1 = math.max(a.x, b.x)
    local y1 = math.max(a.y, b.y)
    local x2 = math.min(a.x + a.w - 1, b.x + b.w - 1)
    local y2 = math.min(a.y + a.h - 1, b.y + b.h - 1)
    if x2 < x1 or y2 < y1 then return nil end
    return {x = x1, y = y1, w = x2 - x1 + 1, h = y2 - y1 + 1}
  end

  function screen.withClip(rect, fn)
    local old = screen.clip
    local base = old or {x = 1, y = 1, w = screen.w, h = screen.h}
    local nextClip = intersect(base, rect)
    if not nextClip then return end
    screen.clip = nextClip
    fn()
    screen.clip = old
  end

  function screen.set(x, y, ch, fg, bg)
    x, y = math.floor(x), math.floor(y)
    if x < 1 or y < 1 or x > screen.w or y > screen.h then return end
    if not insideClip(x, y) then return end

    ch = ch or " "
    fg = fg or C.text
    bg = bg or C.bg

    local b = screen.back[y][x]
    if b.ch ~= ch or b.fg ~= fg or b.bg ~= bg then
      b.ch, b.fg, b.bg = ch, fg, bg
      screen.dirty[y][x] = true
      screen.dirtyRows[y] = true
      screen.hasDirty = true
    end
  end

  function screen.fill(x, y, w, h, ch, fg, bg)
    if w <= 0 or h <= 0 then return end
    ch = ch or " "
    local c = screen.clip
    local x1 = math.max(1, c.x, math.floor(x))
    local y1 = math.max(1, c.y, math.floor(y))
    local x2 = math.min(screen.w, c.x + c.w - 1, math.floor(x + w - 1))
    local y2 = math.min(screen.h, c.y + c.h - 1, math.floor(y + h - 1))
    if x2 < x1 or y2 < y1 then return end
    for yy = y1, y2 do
      for xx = x1, x2 do
        local b = screen.back[yy][xx]
        local nextFg = fg or C.text
        local nextBg = bg or C.bg
        if b.ch ~= ch or b.fg ~= nextFg or b.bg ~= nextBg then
          b.ch, b.fg, b.bg = ch, nextFg, nextBg
          screen.dirty[yy][xx] = true
          screen.dirtyRows[yy] = true
          screen.hasDirty = true
        end
      end
    end
  end

  function screen.text(x, y, text, fg, bg, maxW)
    text = tostring(text or "")
    local len = unicode.len(text)
    local limit = math.min(maxW or len, len)
    for i = 1, limit do
      screen.set(x + i - 1, y, unicode.sub(text, i, i), fg, bg)
    end
  end

  function screen.textRight(rightEdge, y, text, fg, bg)
    text = tostring(text or "")
    screen.text(rightEdge - unicode.len(text) + 1, y, text, fg, bg)
  end

  function screen.clear(bg)
    screen.fill(1, 1, screen.w, screen.h, " ", C.text, bg or C.bg)
  end

  function screen.semi(x, py, color, bg)
    local y = math.ceil(py / 2)
    local top = (py % 2) ~= 0
    screen.set(x, y, top and "▀" or "▄", color, bg or C.bg)
  end

  function screen.markAll()
    for y = 1, screen.h do
      for x = 1, screen.w do
        screen.dirty[y][x] = true
      end
      screen.dirtyRows[y] = true
    end
    screen.hasDirty = true
  end

  function screen.copy(x, y, w, h, dx, dy)
    if w <= 0 or h <= 0 or (dx == 0 and dy == 0) then return end

    local x1 = math.max(1, math.floor(x))
    local y1 = math.max(1, math.floor(y))
    local x2 = math.min(screen.w, math.floor(x + w - 1))
    local y2 = math.min(screen.h, math.floor(y + h - 1))
    if x2 < x1 or y2 < y1 then return end

    local width, height = x2 - x1 + 1, y2 - y1 + 1
    gpu.copy(x1, y1, width, height, dx, dy)

    local yStart, yEnd, yStep = 0, height - 1, 1
    local xStart, xEnd, xStep = 0, width - 1, 1
    if dy > 0 then yStart, yEnd, yStep = height - 1, 0, -1 end
    if dx > 0 then xStart, xEnd, xStep = width - 1, 0, -1 end

    for yy = yStart, yEnd, yStep do
      local srcY = y1 + yy
      local destY = srcY + dy
      if destY >= 1 and destY <= screen.h then
        for xx = xStart, xEnd, xStep do
          local srcX = x1 + xx
          local destX = srcX + dx
          if destX >= 1 and destX <= screen.w then
            local src = screen.back[srcY][srcX]
            local b = screen.back[destY][destX]
            local f = screen.front[destY][destX]
            b.ch, b.fg, b.bg = src.ch, src.fg, src.bg
            f.ch, f.fg, f.bg = src.ch, src.fg, src.bg
            screen.dirty[destY][destX] = nil
          end
        end
      end
    end
  end

  local function setColors(fg, bg)
    if screen.cachedBg ~= bg then
      screen.cachedBg = bg
      gpu.setBackground(bg)
    end
    if screen.cachedFg ~= fg then
      screen.cachedFg = fg
      gpu.setForeground(fg)
    end
  end

  function screen.flush()
    if not screen.hasDirty then return end
    for y = 1, screen.h do
      if screen.dirtyRows[y] then
        local rowDirty = screen.dirty[y]
        local x = 1
        while x <= screen.w do
          if rowDirty[x] then
            local start = x
            local first = screen.back[y][x]
            local fg, bg = first.fg, first.bg
            local out = {}

            while x <= screen.w and rowDirty[x] do
              local cur = screen.back[y][x]
              if cur.fg ~= fg or cur.bg ~= bg then break end
              out[#out + 1] = cur.ch

              local f = screen.front[y][x]
              f.ch, f.fg, f.bg = cur.ch, cur.fg, cur.bg
              rowDirty[x] = nil
              x = x + 1
            end

            setColors(fg, bg)
            gpu.set(start, y, table.concat(out))
          else
            x = x + 1
          end
        end
      end
    end
    screen.dirtyRows = {}
    screen.hasDirty = false
  end

  return screen
end
