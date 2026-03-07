return function(args, api)
  local fs = require("filesystem")

  local recursive = false
  local paths = {}
  for _, a in ipairs(args) do
    if a == "-r" or a == "-rf" or a == "-R" then
      recursive = true
    else
      table.insert(paths, a)
    end
  end

  if #paths == 0 then
    api.print("Usage: rm [-r] <file_or_dir> ...")
    return
  end

  local function removeAll(path)
    if fs.isDir(path) then
      local list = fs.list(path) or {}
      for _, entry in ipairs(list) do
        local child = (path .. "/" .. entry:gsub("/$", ""))
        removeAll(child)
      end
    end
    fs.remove(path)
  end

  for _, path in ipairs(paths) do
    local target = api.resolve(path)
    if target == "/" then
      api.print("rm: refusing to remove root '/'")
    elseif not fs.exists(target) then
      api.print("rm: cannot remove '" .. path .. "': No such file or directory")
    elseif fs.isDir(target) and not recursive then
      api.print("rm: cannot remove '" .. path .. "': Is a directory (use -r)")
    else
      removeAll(target)
    end
  end
end