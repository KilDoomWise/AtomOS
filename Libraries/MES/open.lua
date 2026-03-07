return function(args, api)
  local fs = require("filesystem")
  local proc = require("process")
  
  local path = args[1]
  if not path then
    api.print("Usage: open <app_folder.app>")
    return
  end

  local target = api.resolve(path)
  if not target:match("%.app/?$") then
    api.print("Error: Target must be an .app package")
    return
  end

  if not fs.exists(target) then
    api.print("Error: App not found")
    return
  end

  local ok, err = proc.spawn(target)
  if ok then
    api.print("Launched: " .. target)
  else
    api.print("Launch failed: " .. tostring(err))
  end
end