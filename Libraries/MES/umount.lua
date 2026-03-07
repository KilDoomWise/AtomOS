return function(args, api)
  local gpu = require("graphics")
  local point = args[1]
  if not point then
    api.print("Usage: umount <mountpoint>")
    return
  end
  local ok, err = unit.call("atfs", "umount", point)
  if ok then
    unit.call("atfs", "saveFstab")
    gpu.setForeground(0x00FF88)
    api.print("Unmounted " .. point)
    gpu.setForeground(0xFFFFFF)
  else
    gpu.setForeground(0xFF4444)
    api.print("umount: " .. tostring(err))
    gpu.setForeground(0xFFFFFF)
  end
end
