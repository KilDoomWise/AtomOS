return function(args, api)
  local fs = require("filesystem")

  local src  = args[1]
  local dest = args[2]
  if not src or not dest then
    api.print("Usage: cp <source> <dest>")
    return
  end

  local srcPath  = api.resolve(src)
  local destPath = api.resolve(dest)

  if not fs.exists(srcPath) then
    api.print("cp: '" .. src .. "': No such file or directory")
    return
  end

  -- If dest is an existing directory, copy into it
  if fs.isDir(destPath) then
    local name = srcPath:match("[^/]+/?$"):gsub("/$", "")
    destPath = (destPath == "/" and "/" or destPath .. "/") .. name
  end

  local function copyFile(from, to)
    local data = fs.readAll(from)
    if data == nil then
      api.print("cp: cannot read '" .. from .. "'")
      return false
    end
    local ok = fs.writeAll(to, data)
    if not ok then
      api.print("cp: cannot write '" .. to .. "'")
      return false
    end
    return true
  end

  local function copyDir(from, to)
    fs.makeDir(to)
    local list = fs.list(from) or {}
    for _, entry in ipairs(list) do
      local name = entry:gsub("/$", "")
      local childSrc  = (from == "/" and "/" or from .. "/") .. name
      local childDest = (to   == "/" and "/" or to   .. "/") .. name
      if fs.isDir(childSrc) then
        copyDir(childSrc, childDest)
      else
        copyFile(childSrc, childDest)
      end
    end
  end

  if fs.isDir(srcPath) then
    copyDir(srcPath, destPath)
  else
    copyFile(srcPath, destPath)
  end
end
