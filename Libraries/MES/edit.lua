return function(args, api)
  local fs = require("filesystem")
  local code = fs.readAll("/Apps/Edit.app/main.lua")
  if not code then api.print("edit: /Apps/Edit.app/main.lua not found"); return end
  local fn, err = load(code, "=Edit.app", "bt", _ENV)
  if not fn then api.print("edit: " .. tostring(err)); return end
  local ok, runerr = pcall(fn, args, api)
  if not ok then api.print("edit: " .. tostring(runerr)) end
end