return function(args, api)
  local fs = require("filesystem")
  local path = args[1]
  if not path then
    api.setCwd("/")
    return
  end
  local target = api.resolve(path)
  if fs.isDir(target) then
    api.setCwd(target)
  else
    api.print("cd: " .. path .. ": Not a directory")
  end
end