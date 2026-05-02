local sys_load = ...

_ENV.atom = {
  load = sys_load,
  ring1 = {},
  ring2 = {},
  panic = function(msg)
    local g = component.list("gpu")()
    local s = component.list("screen")()
    if g and s then
      component.invoke(g, "bind", s)
      local w, h = component.invoke(g, "maxResolution")
      component.invoke(g, "setResolution", w, h)
      component.invoke(g, "setBackground", 0x000000)
      component.invoke(g, "setForeground", 0xFF0000)
      component.invoke(g, "fill", 1, 1, w, h, " ")

      local crash_art = {
        "             _                                         ",
        "            | |                                        ",
        "            | |===( )   //////                         ",
        "            |_|   |||  | o o|                          ",
        "                   ||| ( c  )                  ____    ",
        "                    ||| \\= /                  ||   \\_  ",
        "                     ||||||                   ||     | ",
        "                     ||||||                ...||__/|-\" ",
        "                     ||||||              __|________|__",
        "                       |||              |______________|",
        "                       |||              || ||      || ||",
        "                       |||              || ||      || ||",
        "------------------------|||-------------||-||------||-||-------",
        "                       |__>             || ||      || ||"
      }

      local max_width = 0
      for _, line in ipairs(crash_art) do
        if string.len(line) > max_width then
          max_width = string.len(line)
        end
      end

      local y = math.floor(h / 2) - math.floor(#crash_art / 2)
      local x = math.floor(w / 2) - math.floor(max_width / 2)

      for i, line in ipairs(crash_art) do
        component.invoke(g, "set", x, y + i, line)
      end

      local error_y = y + #crash_art + 2
      component.invoke(g, "set", math.floor(w / 2) - 6, error_y, "KERNEL PANIC!")
      
      local msg_str = "=> " .. tostring(msg)
      component.invoke(g, "set", math.floor(w / 2) - math.floor(string.len(msg_str) / 2), error_y + 2, msg_str)

    end
    while true do computer.pullSignal() end
  end
}

local function boot()
  local ok, err = xpcall(function()
    local g_addr = component.list("gpu")()
    local s_addr = component.list("screen")()
    if g_addr and s_addr then
      component.invoke(g_addr, "bind", s_addr)
      component.invoke(g_addr, "setBackground", 0x000000)
      local w, h = component.invoke(g_addr, "maxResolution")
      component.invoke(g_addr, "setResolution", w, h)
      component.invoke(g_addr, "fill", 1, 1, w, h, " ")
      component.invoke(g_addr, "setForeground", 0x00FF00)
      component.invoke(g_addr, "set", 1, 1, "ATOM OS - BOOTING SEQUENCE")
    end

    local y = 3
    local function log(msg)
      if g_addr then
        component.invoke(g_addr, "setForeground", 0x00FF00)
        component.invoke(g_addr, "set", 1, y, "[ OK ] ")
        component.invoke(g_addr, "setForeground", 0xFFFFFF)
        component.invoke(g_addr, "set", 8, y, msg)
        y = y + 1
        local dl = computer.uptime() + 0.1
        while computer.uptime() < dl do end
      end
    end

    log("Initializing Microkernel...")
    atom.ring1.aps = atom.load("/System/aps.lua")()
    log("APS Scheduler Active")

    atom.ring1.atfs = atom.load("/System/atfs.lua")()
    log("ATFS Mounted")

    atom.ring1.agpu = atom.load("/System/agpu.lua")()
    log("AGPU Bound")

    atom.ring1.aio = atom.load("/System/aio.lua")()
    log("AIO Interrupts Hooked")

    atom.ring1.atomui = atom.load("/System/atomui.lua")()
    log("AtomUI Node Online")
    
    atom.ring1.env = atom.load("/System/envbuilder.lua")()
    local user_env = atom.ring1.env.create()
    log("Ring-3 Sandbox Generated")
    
    local mes_spawned, spawn_err = atom.ring1.aps.spawn("/Apps/MES.app/main.lua", "MES", user_env)
    if not mes_spawned then
      error("MES Boot Failed: " .. tostring(spawn_err))
    end
    
    log("Handing over to MES...")
    
    atom.ring1.aps.start()
  end, function(e)
    return tostring(e)
  end)

  if not ok then
    atom.panic(err)
  end
end

boot()
