local gpu     = require("graphics")
local unicode = unicode
local ui      = {}

--------------------------------------------------------------------------------
-- Primitives
--------------------------------------------------------------------------------

-- Fill a rectangle with a solid background color
function ui.drawRect(x, y, w, h, color)
  local ob = gpu.getBackground()
  gpu.setBackground(color)
  gpu.fill(x, y, w, h, " ")
  gpu.setBackground(ob)
end

-- Box-drawing border (no fill)
function ui.drawBorder(x, y, w, h, color)
  local ob, of = gpu.getBackground(), gpu.getForeground()
  gpu.setForeground(color)
  gpu.set(x,       y,       "┌" .. string.rep("─", w - 2) .. "┐")
  gpu.set(x,       y + h - 1, "└" .. string.rep("─", w - 2) .. "┘")
  for i = 1, h - 2 do
    gpu.set(x,         y + i, "│")
    gpu.set(x + w - 1, y + i, "│")
  end
  gpu.setForeground(of)
  gpu.setBackground(ob)
end

-- Circle outline (compensates for OC's 1:2 pixel aspect ratio)
function ui.drawCircle(cx, cy, radius, color)
  local ob = gpu.getBackground()
  gpu.setBackground(color)
  for i = 0, 359 do
    local rad = math.rad(i)
    local x = math.floor(cx + radius * 2 * math.cos(rad) + 0.5)
    local y = math.floor(cy + radius     * math.sin(rad) + 0.5)
    gpu.set(x, y, " ")
  end
  gpu.setBackground(ob)
end

-- Filled circle (aspect-ratio compensated)
function ui.fillCircle(cx, cy, radius, color)
  local ob = gpu.getBackground()
  gpu.setBackground(color)
  for dy = -radius, radius do
    local xw = math.floor(math.sqrt(radius ^ 2 - dy ^ 2) * 2 + 0.5)
    if xw > 0 then
      gpu.fill(cx - math.floor(xw / 2), cy + dy, xw, 1, " ")
    end
  end
  gpu.setBackground(ob)
end

-- Semi-pixel rendering — py is in doubled vertical space
-- py=1 → upper half of terminal row 1, py=2 → lower half of row 1, etc.
function ui.semiPixel(px, py, color)
  local ob, of = gpu.getBackground(), gpu.getForeground()
  local realY  = math.ceil(py / 2)
  local isTop  = (py % 2 ~= 0)
  gpu.setForeground(color)
  gpu.set(px, realY, isTop and "▀" or "▄")
  gpu.setForeground(of)
  gpu.setBackground(ob)
end

-- Horizontal line using box-drawing characters
function ui.hLine(x, y, w, color)
  local of = gpu.getForeground()
  gpu.setForeground(color or 0x555555)
  gpu.set(x, y, string.rep("─", w))
  gpu.setForeground(of)
end

-- Vertical line using box-drawing characters
function ui.vLine(x, y, h, color)
  local of = gpu.getForeground()
  gpu.setForeground(color or 0x555555)
  for i = 0, h - 1 do gpu.set(x, y + i, "│") end
  gpu.setForeground(of)
end

--------------------------------------------------------------------------------
-- Text
--------------------------------------------------------------------------------

-- Draw text at a position with optional fg/bg colors
function ui.label(x, y, text, fg, bg)
  local ob, of = gpu.getBackground(), gpu.getForeground()
  if bg  then gpu.setBackground(bg) end
  if fg  then gpu.setForeground(fg) end
  gpu.set(x, y, text)
  gpu.setForeground(of)
  gpu.setBackground(ob)
end

-- Draw text horizontally centered within a width
function ui.labelCentered(x, y, w, text, fg, bg)
  local tlen = unicode.len(text)
  local pad  = math.max(0, math.floor((w - tlen) / 2))
  ui.label(x + pad, y, text, fg, bg)
end

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------

-- Rendered button (returns the button width so layouts can chain calls)
function ui.button(x, y, text, bgColor, fgColor)
  bgColor = bgColor or 0x3A3A5C
  fgColor = fgColor or 0xFFFFFF
  local bw = unicode.len(text) + 4
  local ob, of = gpu.getBackground(), gpu.getForeground()
  gpu.setBackground(bgColor)
  gpu.setForeground(fgColor)
  gpu.fill(x, y, bw, 1, " ")
  gpu.set(x + 2, y, text)
  gpu.setForeground(of)
  gpu.setBackground(ob)
  return bw
end

-- Horizontal progress bar
function ui.progressBar(x, y, w, value, max, fillColor, bgColor)
  fillColor = fillColor or 0x00AA44
  bgColor   = bgColor   or 0x2A2A2A
  max       = max or 100
  local pct    = math.max(0, math.min(1, value / max))
  local filled = math.floor(w * pct)
  local ob = gpu.getBackground()
  if filled > 0 then
    gpu.setBackground(fillColor)
    gpu.fill(x, y, filled, 1, " ")
  end
  if filled < w then
    gpu.setBackground(bgColor)
    gpu.fill(x + filled, y, w - filled, 1, " ")
  end
  gpu.setBackground(ob)
end

-- Panel: bordered box with optional title embedded in the top edge
-- Example:  ┌── My Panel ──────────────┐
function ui.panel(x, y, w, h, title, bgColor, borderColor, titleColor)
  bgColor     = bgColor     or 0x0D1B2A
  borderColor = borderColor or 0x4A90D9
  titleColor  = titleColor  or 0xE0E0E0

  -- Fill interior
  ui.drawRect(x, y, w, h, bgColor)

  local ob, of = gpu.getBackground(), gpu.getForeground()
  gpu.setBackground(bgColor)

  -- Sides and bottom border
  gpu.setForeground(borderColor)
  gpu.set(x, y + h - 1, "└" .. string.rep("─", w - 2) .. "┘")
  for i = 1, h - 2 do
    gpu.set(x,         y + i, "│")
    gpu.set(x + w - 1, y + i, "│")
  end

  -- Top border (with optional title carved in)
  if title and title ~= "" then
    local tlen = unicode.len(title)
    local dl   = 2                              -- dashes left of title
    local dr   = math.max(0, w - 6 - tlen)     -- dashes right of title

    gpu.setForeground(borderColor)
    gpu.set(x, y, "┌" .. string.rep("─", dl))
    gpu.setForeground(titleColor)
    gpu.set(x + 1 + dl, y, " " .. title .. " ")
    gpu.setForeground(borderColor)
    gpu.set(x + 5 + tlen, y, string.rep("─", dr) .. "┐")
  else
    gpu.set(x, y, "┌" .. string.rep("─", w - 2) .. "┐")
  end

  gpu.setForeground(of)
  gpu.setBackground(ob)
end

-- Checkbox / toggle visual
function ui.checkbox(x, y, label, checked, fgColor)
  local of = gpu.getForeground()
  gpu.setForeground(fgColor or 0xCCCCCC)
  gpu.set(x, y, (checked and "[×] " or "[ ] ") .. label)
  gpu.setForeground(of)
end

-- Vertical scrollbar (thumb shows current viewport position)
function ui.scrollBar(x, y, h, total, visible, offset, thumbColor, trackColor)
  thumbColor = thumbColor or 0x7A7A9A
  trackColor = trackColor or 0x2A2A2A
  local ob = gpu.getBackground()
  gpu.setBackground(trackColor)
  gpu.fill(x, y, 1, h, " ")
  if total > visible then
    local thumbH = math.max(1, math.floor(h * visible / total))
    local maxOff = total - visible
    local thumbY = math.floor((h - thumbH) * math.min(offset, maxOff) / maxOff)
    gpu.setBackground(thumbColor)
    gpu.fill(x, y + thumbY, 1, thumbH, " ")
  end
  gpu.setBackground(ob)
end

-- Static input field render (active=true draws a cursor at end)
function ui.inputField(x, y, w, text, active, bgColor, activeBg, fg)
  bgColor  = bgColor  or 0x1E1E2E
  activeBg = activeBg or 0x2E2E4E
  fg       = fg       or 0xE0E0E0
  local ob, of = gpu.getBackground(), gpu.getForeground()
  gpu.setBackground(active and activeBg or bgColor)
  gpu.setForeground(fg)
  gpu.fill(x, y, w, 1, " ")
  local display = text and unicode.sub(text, 1, w - 2) or ""
  if display ~= "" then gpu.set(x + 1, y, display) end
  if active then
    local curX = x + 1 + unicode.len(text or "")
    if curX <= x + w - 1 then gpu.set(curX, y, "▌") end
  end
  gpu.setForeground(of)
  gpu.setBackground(ob)
end

-- Single-line toast / notification banner
function ui.toast(x, y, w, message, bgColor, fgColor)
  bgColor = bgColor or 0x2D2D4D
  fgColor = fgColor or 0xFFFFFF
  local ob, of = gpu.getBackground(), gpu.getForeground()
  gpu.setBackground(bgColor)
  gpu.setForeground(fgColor)
  gpu.fill(x, y, w, 1, " ")
  gpu.set(x + 1, y, unicode.sub(message, 1, w - 2))
  gpu.setForeground(of)
  gpu.setBackground(ob)
end

-- Simple dropdown / list selector (renders only, no input handling)
-- selectedIdx is 1-based; items is a list of strings
function ui.listBox(x, y, w, items, selectedIdx, bgColor, selBg, fg, selFg)
  bgColor = bgColor or 0x1A1A2E
  selBg   = selBg   or 0x3A3A7C
  fg      = fg      or 0xCCCCCC
  selFg   = selFg   or 0xFFFFFF
  local ob, of = gpu.getBackground(), gpu.getForeground()
  for i, item in ipairs(items) do
    local sel = (i == selectedIdx)
    gpu.setBackground(sel and selBg or bgColor)
    gpu.setForeground(sel and selFg or fg)
    gpu.fill(x, y + i - 1, w, 1, " ")
    gpu.set(x + 1, y + i - 1, unicode.sub(item, 1, w - 2))
  end
  gpu.setForeground(of)
  gpu.setBackground(ob)
end

return ui