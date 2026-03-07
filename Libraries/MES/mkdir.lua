return function(args, api)
  local fs = require("filesystem")
  local path = args[1]
  if not path then
    api.print("Usage: mkdir <directory>")
    return
  end
  local target = api.resolve(path)
  local ok, err = fs.makeDir(target)
  if not ok then
    api.print("mkdir: cannot create directory '" .. path .. "': " .. tostring(err))
  end
end