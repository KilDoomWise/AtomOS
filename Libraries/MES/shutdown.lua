return function(args, api)
  local io = require("io")
  if not api.isRoot() then api.print("shutdown: permission denied"); return end
  api.print("System halted.")
  local ok, err = io.shutdown(false)
  if not ok and err then api.print("shutdown: " .. tostring(err)) end
end
