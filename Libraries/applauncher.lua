local fs = require("filesystem")
local diagnostics = require("diagnostics")

local launcher = {}

local function trimSlash(path)
  path = tostring(path or "")
  while #path > 1 and path:sub(-1) == "/" do
    path = path:sub(1, -2)
  end
  return path
end

local function joinPath(a, b)
  a = trimSlash(a)
  if a == "" or a == "/" then return "/" .. b end
  return a .. "/" .. b
end

local function appNameOf(entry)
  entry = trimSlash(entry)
  return entry:match("^(.-)%.app$") or entry
end

local function isAppPath(path)
  return trimSlash(path):match("%.app$") ~= nil
end

local function resolvePath(spec, api)
  local resolved = api and api.resolve and api.resolve(spec) or spec
  resolved = trimSlash(resolved)

  if not isAppPath(resolved) then
    local withExt = resolved .. ".app"
    if fs.exists(withExt) and fs.isDir(withExt) then
      resolved = withExt
    end
  end

  if not fs.exists(resolved) then
    return nil, "app not found: " .. spec
  end
  if not fs.isDir(resolved) then
    return nil, "not a directory: " .. resolved
  end
  if not isAppPath(resolved) then
    return nil, "not an .app package: " .. resolved
  end

  return resolved
end

local function resolveByName(name)
  local wanted = appNameOf(name):lower()
  local list = fs.list("/Apps") or {}

  for _, entry in ipairs(list) do
    local clean = trimSlash(entry)
    if clean:match("%.app$") and appNameOf(clean):lower() == wanted then
      return "/Apps/" .. clean
    end
  end

  return nil, "app not found: " .. name
end

function launcher.resolve(spec, api)
  if not spec or spec == "" then
    return nil, "missing app name"
  end

  if spec:find("/", 1, true) then
    return resolvePath(spec, api)
  end

  return resolveByName(spec)
end

function launcher.run(spec, args, api, parentEnv, opts)
  local appPath, err = launcher.resolve(spec, api)
  if not appPath then return false, err end

  local mainPath = joinPath(appPath, "main.lua")
  if not fs.exists(mainPath) or fs.isDir(mainPath) then
    return false, "main.lua not found: " .. mainPath
  end

  local code = fs.readAll(mainPath)
  if not code then
    return false, "cannot read: " .. mainPath
  end

  local env = setmetatable({}, {__index = parentEnv or _ENV})
  env._G = env

  local fn, loadErr = load(code, "=" .. mainPath, "bt", env)
  if not fn then return false, diagnostics.message(loadErr, appPath) end

  local fgToken
  if unit and unit.call then
    local ctx = opts or (api and api.securityContext and api.securityContext()) or nil
    fgToken = unit.call("aps", "enterForeground", appPath, ctx)
  end

  local function runForeground()
    local co = coroutine.create(function()
      return fn(args or {}, api)
    end)

    local ok, runErr = coroutine.resume(co)
    if not ok then return false, diagnostics.make(runErr, co, appPath) end

    while coroutine.status(co) ~= "dead" do
      local sig = {coroutine.yield()}
      if sig[1] == "atom_interrupt" then
        return false, "interrupted"
      end

      ok, runErr = coroutine.resume(co, table.unpack(sig))
      if not ok then return false, diagnostics.make(runErr, co, appPath) end
    end

    return true, appPath
  end

  local ok, res1, res2 = pcall(runForeground)

  if unit and unit.call then
    unit.call("aps", "leaveForeground", fgToken)
  end

  if not ok then return false, diagnostics.make(res1, nil, appPath) end
  if not res1 then return false, res2 end

  return true, appPath
end

return launcher
