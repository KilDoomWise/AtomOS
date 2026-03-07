return function(args, api)
  local auth = require("auth")
  if not api.isRoot() then api.print("useradd: permission denied"); return end

  local name = args[1] or api.readLine("Username: ")
  name = name:match("^%s*(.-)%s*$")
  if name == "" then api.print("useradd: empty username"); return end

  local p1 = api.readPassword("Password (leave blank for none): ")
  if p1 ~= "" then
    local p2 = api.readPassword("Retype password: ")
    if p1 ~= p2 then api.print("useradd: passwords do not match"); return end
  end

  local ok, err = auth.addUser(name, p1)
  if ok then
    api.print("useradd: user '" .. name .. "' created (home: /home/" .. name .. ")")
  else
    api.print("useradd: " .. tostring(err))
  end
end
