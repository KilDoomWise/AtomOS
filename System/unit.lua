local unit = {}
local r1 = _G.atom.ring1

function unit.call(svc, fn, ...)
  if not r1[svc] then 
    return nil, "svc_not_found" 
  end
  if type(r1[svc][fn]) ~= "function" then 
    return nil, "fn_not_found" 
  end
  
  local ok, res1, res2, res3 = pcall(r1[svc][fn], ...)
  if not ok then
    return nil, res1
  end
  return res1, res2, res3
end

return unit