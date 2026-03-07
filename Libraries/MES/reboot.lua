return function(args, api)
  local io = require("io")
  api.print("Rebooting Atom OS...")
  io.shutdown(true)
end