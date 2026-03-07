return function(args, api)
  local auth = require("auth")
  if not api.isRoot() then api.print("userdel: permission denied"); return end

  local name = args[1]
  if not name then api.print("Usage: userdel <username>"); return end
  if name == api.getUser().name then
    api.print("userdel: cannot delete the currently logged-in user")
    return
  end

  local ok, err = auth.delUser(name)
  if ok then
    api.print("userdel: user '" .. name .. "' removed")
  else
    api.print("userdel: " .. tostring(err))
  end
end
