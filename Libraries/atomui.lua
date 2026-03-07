local gpu = require("graphics")
local ui = {}

function ui.drawRect(x, y, w, h, color)
  local oldBg = gpu.getBackground()
  gpu.setBackground(color)
  gpu.fill(x, y, w, h, " ")
  gpu.setBackground(oldBg)
end

function ui.drawCircle(cx, cy, radius, color)
  local oldBg = gpu.getBackground()
  gpu.setBackground(color)
  
  for i = 0, 360, 1 do
    local rad = math.rad(i)
    local x = math.floor(cx + (radius * 2) * math.cos(rad) + 0.5)
    local y = math.floor(cy + radius * math.sin(rad) + 0.5)
    gpu.set(x, y, " ")
  end
  
  gpu.setBackground(oldBg)
end

function ui.fillCircle(cx, cy, radius, color)
  local oldBg = gpu.getBackground()
  gpu.setBackground(color)
  
  for y = -radius, radius do
    local x_width = math.floor(math.sqrt(radius^2 - y^2) * 2 + 0.5)
    if x_width > 0 then
      gpu.fill(cx - math.floor(x_width/2), cy + y, x_width, 1, " ")
    end
  end
  
  gpu.setBackground(oldBg)
end

-- Semi-pixel рендеринг (удвоенное разрешение по вертикали)
-- Координаты py передаются в виртуальном удвоенном пространстве!
  local oldFg = gpu.getForeground()
  
  local realY = math.ceil(py / 2)
  local isTop = (py % 2 ~= 0)
  
  if isTop then
    gpu.setForeground(color)
    -- Рисуем верхнюю половинку (▀)
    gpu.set(px, realY, "▀")
  elgpu.set(px, realY, "▀")
  else
    gpu.setForeground(color
  
  gpu.setBackground(oldBg)
  gpu.setForeground(oldFg)
end

return ui