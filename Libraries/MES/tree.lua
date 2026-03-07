return function(args, api)
  local fs = require("filesystem")
  local gpu = require("graphics")
  
  local start_path = args[1] and api.resolve(args[1]) or api.getCwd()
  
  local fbm = "├─ "
  local lbm = "└─ "
  local vbm = "│  "
  local sbm = "   "
  
  local function walk(path, prefix)
    local list = fs.list(path) or {}
    -- Sort dirs first
    table.sort(list, function(a, b)
      local aDir = a:sub(-1) == "/"
      local bDir = b:sub(-1) == "/"
      if aDir and not bDir then return true end
      if not aDir and bDir then return false end
      return a:lower() < b:lower()
    end)
    
    for i, file in ipairs(list) do
      local isLast = (i == #list)
      local isDir = file:sub(-1) == "/"
      local name = isDir and file:sub(1, -2) or file
      
      gpu.setForeground(0x555555)
      api.write(prefix)
      api.write(isLast and lbm or fbm)
      
      if isDir then
        gpu.setForeground(0x00AAFF) -- Blue dir
        api.print("» " .. name)
        walk(path .. "/" .. name, prefix .. (isLast and sbm or vbm))
      else
        gpu.setForeground(0xFFFFFF) -- White file
        api.print("• " .. name)
      end
    end
  end
  
  gpu.setForeground(0x00AAFF)
  api.print(start_path)
  walk(start_path, "")
  gpu.setForeground(0xFFFFFF)
end