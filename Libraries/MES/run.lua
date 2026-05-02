return function(args, api)
  local launcher = require("applauncher")
  local diagnostics = require("diagnostics")

  local spec = args[1]
  if not spec then
    api.print("Usage: run <app_name|path.app> [args...]")
    api.print("Examples: run Edit /init.lua")
    api.print("          run /home/MyApp.app")
    return
  end

  local appArgs = {}
  for i = 2, #args do
    appArgs[#appArgs + 1] = args[i]
  end

  local ok, err = launcher.run(spec, appArgs, api, _ENV)
  if not ok then
    if err == "interrupted" then
      api.print("^C")
    elseif type(err) == "table" then
      diagnostics.render(err, api, { title = "Application crashed" })
    else
      api.print("run: " .. tostring(err))
    end
  end
end
