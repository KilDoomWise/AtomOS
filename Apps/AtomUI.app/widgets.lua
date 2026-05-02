return function(state)
  local unicode = require("unicode")
  local screen = state.screen
  local C = state.theme.color
  local L = state.theme.layout
  local S = state.theme.symbol
  local widgets = {}

  local function cut(text, w)
    text = tostring(text or "")
    if unicode.len(text) <= w then return text end
    if w <= 1 then return unicode.sub(text, 1, w) end
    return unicode.sub(text, 1, w - 1) .. "…"
  end

  widgets.cut = cut

  function widgets.label(x, y, text, fg, bg, w)
    screen.text(x, y, cut(text, w or 9999), fg or C.text, bg or C.bg)
  end

  function widgets.labelRight(right, y, text, fg, bg)
    screen.textRight(right, y, text, fg or C.text, bg or C.bg)
  end

  function widgets.divider(x, y, w, bg)
    screen.fill(x, y, w, 1, "─", C.divider, bg or C.accent)
  end

  function widgets.squareMark(x, y, color, bg, glyph)
    bg = bg or C.bg
    screen.fill(x, y, 2, 1, " ", C.text, color)
    if glyph and glyph ~= "" then
      screen.text(x, y, glyph, C.text, color, 1)
    end
    screen.set(x + 2, y, " ", C.text, bg)
  end

  function widgets.button3(x, y, w, label, active, glyph)
    local bg = active and C.active or C.accent
    screen.fill(x, y, w, 3, " ", C.text, bg)
    label = tostring(label or "")
    if glyph and glyph ~= "" and label == "" then
      screen.text(x + math.floor((w - 1) / 2), y + 1, glyph, C.text, bg, 1)
      return
    end
    local text = (glyph and glyph ~= "" and (glyph .. " ") or "") .. label
    screen.text(x + 2, y + 1, cut(text, math.max(1, w - 4)), C.text, bg)
  end

  function widgets.button1(x, y, w, label, active, glyph)
    local bg = active and C.active or C.accent
    screen.fill(x, y, w, 1, " ", C.text, bg)
    local text = (glyph and glyph ~= "" and (glyph .. " ") or "") .. tostring(label or "")
    screen.text(x + 1, y, cut(text, math.max(1, w - 2)), C.text, bg)
  end

  function widgets.menuItemHeight(item)
    if item.separator or item.disabled then return 1 end
    return 2
  end

  function widgets.menuItem(x, y, w, item, selected)
    if item.separator then
      widgets.divider(x + 1, y, w - 2, C.accent)
      return 1
    end
    if item.disabled then
      local text = (item.icon and item.icon ~= "" and (item.icon .. " ") or "") .. item.label
      screen.text(x + L.menuPadX, y, cut(text, w - L.menuPadX * 2), C.muted, C.accent)
      return 1
    end

    local bg = selected and C.active or C.accent
    screen.fill(x, y, w, 2, " ", C.text, bg)
    local text = (item.icon and item.icon ~= "" and (item.icon .. " ") or "") .. item.label
    screen.text(x + L.menuPadX, y, cut(text, w - L.menuPadX * 2), C.text, bg)
    return 2
  end

  function widgets.progress(x, y, w, value, max, fg, bg)
    max = max or 1
    if max <= 0 then max = 1 end
    local pct = math.max(0, math.min(1, value / max))
    local filled = math.floor(w * pct + 0.5)
    screen.fill(x, y, w, 1, " ", C.text, bg or C.accent)
    if filled > 0 then
      screen.fill(x, y, filled, 1, " ", C.text, fg or C.ok)
    end
  end

  function widgets.semiMeter(x, y, w, value, max, fg, bg)
    max = max or 1
    if max <= 0 then max = 1 end
    fg = fg or C.ok
    bg = bg or C.accent
    local pct = math.max(0, math.min(1, value / max))
    local units = math.floor((w * 2) * pct + 0.5)
    for i = 1, w do
      local cellUnits = units - ((i - 1) * 2)
      local ch = " "
      if cellUnits >= 2 then ch = "█"
      elseif cellUnits == 1 then ch = "▀" end
      screen.set(x + i - 1, y, ch, fg, bg)
    end
  end

  function widgets.thinBar(x, y, w, value, max, fg, bg)
    max = max or 1
    if max <= 0 then max = 1 end
    local pct = math.max(0, math.min(1, value / max))
    local filled = math.floor(w * pct + 0.5)
    if w <= 0 then return pct end
    screen.fill(x, y, w, 1, "─", bg or C.divider, C.panel)
    if filled > 0 then screen.fill(x, y, filled, 1, "━", fg or C.info, C.panel) end
    return pct
  end

  function widgets.checkbox(x, y, label, checked, active, bg)
    bg = bg or C.window
    local mark = checked and "☑" or "☐"
    screen.text(x, y, mark, active and C.info or C.subtext, bg)
    screen.text(x + 2, y, label, active and C.text or C.subtext, bg)
  end

  function widgets.logo(x, y, bg)
    bg = bg or C.bg
    local lines = {
      "┌────┐",
      "│ " .. S.logo .. "  │",
      "└────┘"
    }
    for i, line in ipairs(lines) do
      screen.text(x, y + i - 1, line, C.text, bg)
    end
  end

  function widgets.appIcon(x, y, label, glyph, tint, selected, bg, cellW)
    bg = bg or C.bg
    tint = tint or C.accent
    local iw, ih = L.iconGlyphW, L.iconGlyphH
    local fillBg = selected and C.selected or tint
    local cw = cellW or iw
    local gx = x + math.max(0, math.floor((cw - iw) / 2))

    screen.fill(x, y, cw, ih + 2, " ", C.text, bg)
    screen.fill(gx, y, iw, ih, " ", C.text, fillBg)
    screen.text(gx, y, "┌────┐", C.divider, fillBg)
    screen.text(gx, y + 1, "│    │", C.divider, fillBg)
    screen.text(gx, y + 2, "└────┘", C.divider, fillBg)
    screen.text(gx + 2, y + 1, glyph or S.app, C.text, fillBg, 1)

    local labelText = cut(label or "", cw)
    local tx = x + math.max(0, math.floor((cw - unicode.len(labelText)) / 2))
    screen.text(tx, y + ih + 1, labelText, selected and C.text or C.subtext, bg)
  end

  function widgets.toast(x, y, w, text, kind)
    local bg = C.accent2
    if kind == "ok" then bg = C.ok
    elseif kind == "warn" then bg = C.warn
    elseif kind == "danger" then bg = C.danger end
    local fg = (kind == "ok" or kind == "warn" or kind == "danger") and C.bg or C.text
    screen.fill(x, y, w, 1, " ", fg, bg)
    screen.text(x + 1, y, cut(text, w - 2), fg, bg)
  end

  return widgets
end
