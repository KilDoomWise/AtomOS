return function(args, api)
  local auth = require("auth")
  -- passwd [username]  — root can change anyone, users change only themselves
  local target = args[1] or api.getUser().name
  if target ~= api.getUser().name and not api.isRoot() then
    api.print("passwd: permission denied")
    return
  end
  -- Non-root must verify current password first
  if not api.isRoot() then
    local cur = api.readPassword("Current password: ")
    if not auth.verify(target, cur) then
      api.print("passwd: authentication failure")
      return
    end
  end
  local p1 = api.readPassword("New password: ")
  local p2 = api.readPassword("Retype new password: ")
  if p1 ~= p2 then api.print("passwd: passwords do not match"); return end
  local ok, err = auth.setPassword(target, p1)
  if ok then
    api.print("passwd: password updated for " .. target)
  else
    api.print("passwd: " .. tostring(err))
  end
end
