return function(args, api)
  local fs = require("filesystem")
  local gpu = require("graphics")
  
  local path = args[1]
  local target = path and api.resolve(path) or api.getCwd()
  local list = fs.list(target)
  
  if list then
    -- Сортировка: Сначала папки, потом файлы
    table.sort(list, function(a, b)
      local aIsDir = a:sub(-1) == "/"
      local bIsDir = b:sub(-1) == "/"
      if aIsDir and not bIsDir then return true end
      if not aIsDir and bIsDir then return false end
      return a:lower() < b:lower()
    end)

    local w, _ = gpu.getResolution()
    local colWidth = 0

    for _, v in ipairs(list) do
      if #v > colWidth then colWidth = #v end
    end
    colWidth = colWidth + 2

    local cols = math.floor(w / colWidth)
    if cols < 1 then cols = 1 end

    local current_col = 0

    for _, v in ipairs(list) do
      local isDir = v:sub(-1) == "/"
      local ext = v:match("%.([^./]+)/?$")

      if isDir then
        if v:find("%.app/$") then
          gpu.setForeground(0x00FFFF)
        else
          gpu.setForeground(0x4499FF)
        end
      elseif ext == "lua" then
        gpu.setForeground(0x88FF88)
      elseif ext == "cfg" or ext == "lang" or ext == "txt" then
        gpu.setForeground(0xAAAAAA)
      else
        gpu.setForeground(0xFFFFFF)
      end

      api.write(string.format("%-" .. colWidth .. "s", v))
      current_col = current_col + 1

      if current_col >= cols then
        api.write("\n")
        current_col = 0
      end
    end
    if current_col > 0 then api.write("\n") end

    gpu.setForeground(0xFFFFFF)
  else
    api.print("ls: cannot access '" .. target .. "': No such file or directory")
  end
end