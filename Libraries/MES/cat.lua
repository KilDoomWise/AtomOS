return function(args, api)
  local fs = require("filesystem")
  local path = args[1]
  if not path then api.print("Usage: cat <file>"); return end
  local target = api.resolve(path)
  if fs.isDir(target) then
    api.print("cat: " .. path .. ": Is a directory")
    return
  end
  local data = fs.readAll(target)
  if data then
    api.print(data)
  else
    api.print("cat: " .. path .. ": No such file")
  end
end