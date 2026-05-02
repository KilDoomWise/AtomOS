return function(args, api)
  local launcher = require("applauncher")
  local diagnostics = require("diagnostics")

  local ok, err = launcher.run("AtomUI", args, api, _ENV)
  if not ok then
    if err == "interrupted" then
      api.print("^C")
    elseif type(err) == "table" then
      diagnostics.render(err, api, {title = "AtomUI crashed"})
    else
      api.print("atomui: " .. tostring(err))
    end
  end
end
