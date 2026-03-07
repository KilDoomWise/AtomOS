return function(args, api)
  local internet = require("internet")
  local fs = require("filesystem")
  local gpu = require("graphics")

  if not internet then
    api.print("Error: No internet card found.")
    return
  end

  local url = args[1]
  local filename = args[2]

  if not url then
    api.print("Usage: wget <url> [filename]")
    return
  end
  
  if not filename then
    -- Пытаемся угадать имя файла из URL
    filename = url:match(".*/([^/?]+)") or "index.html"
  end
  
  local target = api.resolve(filename)
  
  api.print("Connecting to " .. url .. "...")
  local handle, err = internet.request(url)
  if not handle then
    api.print("Error: " .. tostring(err))
    return
  end

  api.print("Downloading...")
  local data = ""
  while true do
    local chunk = handle.read(math.huge)
    if not chunk then break end
    data = data .. chunk
    gpu.fill(1, 19, 1, 1, ".") -- Индикатор активности (просто точка где-то)
  end
  handle.close()

  api.print("Saving to " .. target .. " ...")
  local f = fs.open(target, "w")
  if f then
    fs.write(f, data)
    fs.close(f)
    api.print("Done! (" .. #data .. " bytes)")
  else
    api.print("Error: Could not open file for writing.")
  end
end