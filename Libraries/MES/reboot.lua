return function(args, api)
  local io = require("io")
  if not api.isRoot() then api.print("reboot: permission denied"); return end
  api.print("Rebooting Atom OS...")
  local ok, err = io.shutdown(true)
  if not ok and err then api.print("reboot: " .. tostring(err)) end
end
