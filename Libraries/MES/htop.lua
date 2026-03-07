return function(args, api)
  local gpu = require("graphics")
  local proc = require("process")
  local io = require("io")

  local w, h = gpu.getResolution()
  local running = true
  local selected = 1

  local function draw()
    local tasks = proc.list() or {}
    if selected > #tasks then selected = math.max(1, #tasks) end

    gpu.setBackground(0x000000)
    gpu.setForeground(0xFFFFFF)
    gpu.fill(1, 1, w, h, " ")

    gpu.setBackground(0x00AA00)
    gpu.setForeground(0xFFFFFF)
    gpu.fill(1, 1, w, 1, " ")
    gpu.set(1, 1, " ATOM HTOP - Process Viewer ")

    gpu.setBackground(0x333333)
    gpu.set(1, 2, " PID   STATUS      NAME" .. string.rep(" ", w - 23))

    gpu.setBackground(0x000000)
    for i, t in ipairs(tasks) do
      if i == selected then
        gpu.setBackground(0xFFFFFF)
        gpu.setForeground(0x000000)
      else
        gpu.setBackground(0x000000)
        gpu.setForeground(0xFFFFFF)
      end
      local line = string.format(" %-4d  %-10s  %s", t.id, t.status, t.name)
      line = line .. string.rep(" ", w - #line)
      gpu.set(1, i + 2, line)
    end

    gpu.setBackground(0xAAAAAA)
    gpu.setForeground(0x000000)
    gpu.fill(1, h, w, 1, " ")
    gpu.set(1, h, " [Up/Down] Select   [K] Kill   [Q] Quit ")
    
    gpu.setBackground(0x000000)
    gpu.setForeground(0xFFFFFF)
  end

  draw()
  local last = io.uptime()

  while running do
    local sig = {coroutine.yield()}
    local e = sig[1]
    local redraw = false

    if e == "key_down" then
      local char, code = sig[3], sig[4]
      if char == 113 or char == 81 then -- Q
        running = false
      elseif char == 107 or char == 75 then -- K
        local tasks = proc.list()
        if tasks and tasks[selected] then
          proc.kill(tasks[selected].id)
        end
        redraw = true
      elseif code == 200 then -- Up
        selected = selected - 1
        if selected < 1 then selected = 1 end
        redraw = true
      elseif code == 208 then -- Down
        local tasks = proc.list()
        selected = selected + 1
        if tasks and selected > #tasks then selected = #tasks end
        redraw = true
      end
    end

    -- Автообновление каждую секунду
    if io.uptime() - last > 1 or redraw then
      draw()
      last = io.uptime()
    end
  end

  api.clear()
end