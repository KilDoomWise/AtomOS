return function(args, api)
  local fs = require("filesystem")
  local path = args[1]
  if not path then
    api.print("Usage: rm <file_or_directory>")
    return
  end
  local target = api.resolve(path)
  
  -- Защита от дурака, чтобы не снести корень
  if target == "/" or target == "" then
    api.print("rm: it is forbidden to remove '/'")
    return
  end
  
  if fs.exists(target) then
    local ok, err = fs.remove(target)
    if not ok then
      api.print("rm: cannot remove '" .. path .. "': " .. tostring(err))
    end
  else
    api.print("rm: cannot remove '" .. path .. "': No such file or directory")
  end
end