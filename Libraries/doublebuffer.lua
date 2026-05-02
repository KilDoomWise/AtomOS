local gpu = require("graphics")

local db = {}

local function supported()
  if type(gpu.getActiveBuffer) ~= "function" or type(gpu.allocateBuffer) ~= "function" or type(gpu.bitblt) ~= "function" then
    return false
  end
  local active = gpu.getActiveBuffer()
  return active ~= nil
end

function db.supported()
  return supported()
end

function db.create(w, h)
  if not supported() then return nil, "buffer_api_unavailable" end
  if not w or not h then w, h = gpu.getResolution() end
  local id, err = gpu.allocateBuffer(w, h)
  if not id then return nil, err or "allocate_failed" end
  return {id = id, w = w, h = h, old = 0}
end

function db.begin(buffer, clear, bg)
  if not buffer or not buffer.id then return nil, "bad_buffer" end
  buffer.old = gpu.getActiveBuffer() or 0
  local ok, err = gpu.setActiveBuffer(buffer.id)
  if not ok then return nil, err or "set_active_failed" end
  if bg then gpu.setBackground(bg) end
  if clear then gpu.fill(1, 1, buffer.w, buffer.h, " ") end
  return true
end

function db.commit(buffer, x, y, w, h, fromX, fromY)
  if not buffer or not buffer.id then return nil, "bad_buffer" end
  local active = gpu.getActiveBuffer()
  if active == buffer.id then gpu.setActiveBuffer(buffer.old or 0) end
  return gpu.bitblt(0, x or 1, y or 1, w or buffer.w, h or buffer.h, buffer.id, fromX or 1, fromY or 1)
end

function db.finish(buffer, x, y, w, h, fromX, fromY)
  return db.commit(buffer, x, y, w, h, fromX, fromY)
end

function db.draw(buffer, fn, ...)
  if type(fn) ~= "function" then return nil, "bad_callback" end
  if not buffer or not buffer.id then return fn(...) end
  local ok, err = db.begin(buffer)
  if not ok then return fn(...) end
  local results = {pcall(fn, ...)}
  gpu.setActiveBuffer(buffer.old or 0)
  if not results[1] then error(results[2]) end
  db.commit(buffer)
  return results[2], results[3], results[4], results[5]
end

function db.free(buffer)
  if not buffer or not buffer.id then return false end
  local active = gpu.getActiveBuffer()
  if active == buffer.id then gpu.setActiveBuffer(buffer.old or 0) end
  local ok = gpu.freeBuffer(buffer.id)
  buffer.id = nil
  return ok
end

function db.resize(buffer, w, h)
  if not buffer then return db.create(w, h) end
  if buffer.w == w and buffer.h == h and buffer.id then return buffer end
  db.free(buffer)
  return db.create(w, h)
end

return db
