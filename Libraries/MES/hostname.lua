return function(args, api)
  if not args[1] then
    api.print(api.getHostname())
    return
  end
  if not api.isRoot() then
    api.print("hostname: permission denied")
    return
  end
  local ok, err = api.setHostname(args[1])
  if not ok then api.print("hostname: " .. tostring(err)) end
end
