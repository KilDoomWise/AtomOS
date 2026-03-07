return function(args, api)
  if #args > 0 then
    api.print(table.concat(args, " "))
  else
    api.print("")
  end
end