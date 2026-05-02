return function(args, api)
  local auth = require("auth")
  local target = args[1] or "root"
  if not auth.getUser(target) then
    api.print("su: user '" .. target .. "' does not exist")
    return
  end
  -- Only root can su without a password; others must authenticate as target user
  local pw = nil
  if not api.isRoot() then
    pw = api.readPassword("Password: ")
    if not auth.verify(target, pw) then
      api.print("su: authentication failure")
      return
    end
  elseif target ~= "root" then
    -- root switching to another user: allow without password (Linux behavior)
  end
  local ok, err = api.login(target, pw)
  if ok then
    api.print("switched to " .. target)
  else
    api.print("su: " .. tostring(err))
  end
end
