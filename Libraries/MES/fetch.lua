return function(args, api)
  local gpu = require("graphics")
  local io = require("io")

  local w, h = gpu.getResolution()
  
  -- Красиво считаем аптайм
  local up = math.floor(io.uptime() or 0)
  local up_str = ""
  if up > 3600 then
    up_str = math.floor(up / 3600) .. "h " .. math.floor((up % 3600) / 60) .. "m"
  elseif up > 60 then
    up_str = math.floor(up / 60) .. "m " .. (up % 60) .. "s"
  else
    up_str = up .. "s"
  end

  -- ASCII Логотип Атома
  local logo = {
    "    _.-._    ",
    "  .'  |  '.  ",
    " / -~ O ~- \\ ",
    " '.   |   .' ",
    "   '-...-'   "
  }

  local info = {
    "root@atom",
    "---------",
    "OS: Atom OS v0.1",
    "Host: OpenComputers",
    "Kernel: Microkernel",
    "Uptime: " .. up_str,
    "Shell: MES",
    "Res: " .. w .. "x" .. h
  }

  api.print("")
  for i = 1, math.max(#logo, #info) do
    -- Рисуем логотип (циановый)
    if logo[i] then
      gpu.setForeground(0x00FFFF)
      api.write("  " .. logo[i] .. "  ")
    else
      api.write(string.rep(" ", 17))
    end

    -- Рисуем инфу
    if info[i] then
      if i == 1 then
        gpu.setForeground(0x00FF00) -- Зеленый ник
      elseif i == 2 then
        gpu.setForeground(0xAAAAAA) -- Серый разделитель
      else
        -- Цветные префиксы
        local prefix, val = info[i]:match("([^:]+): (.*)")
        if prefix then
          gpu.setForeground(0x00FFFF)
          api.write(prefix .. ": ")
          gpu.setForeground(0xFFFFFF)
          api.write(val)
        else
          gpu.setForeground(0xFFFFFF)
          api.write(info[i])
        end
      end
    end
    api.write("\n")
  end

  -- Рисуем цветную палитру внизу (классика neofetch)
  gpu.setForeground(0x00FFFF)
  api.write(string.rep(" ", 17))
  local colors = {0x000000, 0xFF0000, 0x00FF00, 0xFFFF00, 0x0000FF, 0xFF00FF, 0x00FFFF, 0xFFFFFF}
  for _, c in ipairs(colors) do
    gpu.setBackground(c)
    api.write("  ")
  end
  gpu.setBackground(0x000000)
  gpu.setForeground(0xFFFFFF)
  api.print("\n")
end