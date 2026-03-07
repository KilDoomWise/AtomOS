return function(args, api)
  local io = require("io")
  api.print("System halted.")
  io.shutdown(false)
end