return function(args, api)
  local fs = require("filesystem")

  local src  = args[1]
  local dest = args[2]
  if not src or not dest then
    api.print("Usage: mv <source> <dest>")
    return
  end

  local srcPath  = api.resolve(src)
  local destPath = api.resolve(dest)

  if not fs.exists(srcPath) then
    api.print("mv: '" .. src .. "': No such file or directory")
    return
  end

  if srcPath == "/" then
    api.print("mv: refusing to move '/'")
    return
  end

  -- If dest is an existing directory, move into it
  if fs.isDir(destPath) then
    local name = srcPath:match("[^/]+/?$"):gsub("/$", "")
    destPath = (destPath == "/" and "/" or destPath .. "/") .. name
  end

  if fs.exists(destPath) and not fs.isDir(destPath) then
    fs.remove(destPath)
  end

  local function copyFile(from, to)
    local data = fs.readAll(from)
    if data == nil then api.print("mv: cannot read '" .. from .. "'"); return false end
    if not fs.writeAll(to, data) then api.print("mv: cannot write '" .. to .. "'"); return false end
    return true
  end

  local function copyDir(from, to)
    fs.makeDir(to)
    local list = fs.list(from) or {}
    for _, entry in ipairs(list) do
      local name = entry:gsub("/$", "")
      local cs = (from == "/" and "/" or from .. "/") .. name
      local cd = (to   == "/" and "/" or to   .. "/") .. name
      if fs.isDir(cs) then copyDir(cs, cd) else copyFile(cs, cd) end
    end
  end

  local function removeAll(path)
    if fs.isDir(path) then
      local list = fs.list(path) or {}
      for _, entry in ipairs(list) do
        removeAll((path == "/" and "/" or path .. "/") .. entry:gsub("/$", ""))
      end
    end
    fs.remove(path)
  end

  if fs.isDir(srcPath) then
    copyDir(srcPath, destPath)
  else
    if not copyFile(srcPath, destPath) then return end
  end
  removeAll(srcPath)
end
