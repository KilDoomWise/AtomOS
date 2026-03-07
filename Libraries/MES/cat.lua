return function(args, api)
  local fs = require("filesystem")
  local path = args[1]
  if not path then return end
  local target = (api.getCwd() .. "/" .. path):gsub("//+", "/")
  local data = fs.readAll(target)
  if data then
    api.print(data)
  else
    api.print("cat: " .. path .. ": No such file")
  end
end