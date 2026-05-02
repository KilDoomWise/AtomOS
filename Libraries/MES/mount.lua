return function(args, api)
  local gpu = require("graphics")

  -- No args: show mounts + known devices
  if #args == 0 then
    local mls = unit.call("atfs", "listMounts")
    local devs = unit.call("atfs", "listDevices")

    gpu.setForeground(0x00FFFF)
    api.print("MOUNTS:")
    gpu.setForeground(0x555555)
    api.print("  " .. string.rep("─", 44))
    if mls then
      for _, m in ipairs(mls) do
        local tag = m.label and (" [" .. m.label .. "]") or ""
        if m.point == "/" then
          gpu.setForeground(0x00FF88)
          api.print(string.format("  %-14s  %s (boot)%s", m.point, m.addr:sub(1,8).."...", tag))
        else
          gpu.setForeground(0xFFFFFF)
          api.print(string.format("  %-14s  %s...%s", m.point, m.addr:sub(1,8), tag))
        end
      end
    end

    if devs and #devs > 0 then
      gpu.setForeground(0x00FFFF)
      api.print("")
      api.print("AVAILABLE DEVICES (not mounted):")
      gpu.setForeground(0x555555)
      api.print("  " .. string.rep("─", 44))
      for _, d in ipairs(devs) do
        local tag = d.label and (" [" .. d.label .. "]") or ""
        local mounted = d.mountedAt and (" → " .. d.mountedAt) or ""
        if d.mountedAt then
          gpu.setForeground(0x888888)
        else
          gpu.setForeground(0x4499FF)
        end
        api.print(string.format("  /dev/%-8s  %s...%s%s", d.id, d.addr:sub(1,8), tag, mounted))
      end
    end

    gpu.setForeground(0xFFFFFF)
    return
  end

  -- -r / --rescan: re-discover connected filesystems
  if args[1] == "-r" or args[1] == "--rescan" then
    local ok, err = unit.call("atfs", "rescan")
    if ok then
      api.print("Rescanned connected drives. Run 'mount' to see the list.")
    else
      api.print("mount: " .. tostring(err))
    end
    return
  end

  -- -u <mountpoint>: unmount
  if args[1] == "-u" then
    local point = args[2]
    if not point then api.print("Usage: mount -u <mountpoint>"); return end
    local ok, err = unit.call("atfs", "umount", point)
    if ok then
      unit.call("atfs", "saveFstab")
      gpu.setForeground(0x00FF88);  api.print("Unmounted " .. point)
    else
      gpu.setForeground(0xFF4444);  api.print("mount: " .. tostring(err))
    end
    gpu.setForeground(0xFFFFFF)
    return
  end

  -- mount <device> <mountpoint>
  local dev, point = args[1], args[2]
  if not dev or not point then
    api.print("Usage:")
    api.print("  mount                    — list mounts and available devices")
    api.print("  mount /dev/xxxxx /path   — mount a device at a path")
    api.print("  mount -u /path           — unmount")
    api.print("  mount -r                 — rescan for new drives")
    return
  end

  -- Resolve /dev/xxxxx to a short ID then let atfs.mount handle it
  local shortId = dev:match("^/dev/([^/]+)$")
  local ok, err = unit.call("atfs", "mount", point, shortId or dev)
  if ok then
    unit.call("atfs", "saveFstab")
    gpu.setForeground(0x00FF88);  api.print(dev .. " mounted at " .. point)
  else
    gpu.setForeground(0xFF4444);  api.print("mount: " .. tostring(err))
  end
  gpu.setForeground(0xFFFFFF)
end
