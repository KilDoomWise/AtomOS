local event = {
  handlers = {}
}

-- Зарегистрировать коллбэк на событие
function event.listen(name, callback)
  if not event.handlers[name] then
    event.handlers[name] = {}
  end
  table.insert(event.handlers[name], callback)
end

-- Удалить коллбэк
function event.ignore(name, callback)
  if event.handlers[name] then
    for i, cb in ipairs(event.handlers[name]) do
      if cb == callback then
        table.remove(event.handlers[name], i)
        return true
      end
    end
  end
  return false
end

-- Синхронно ждать конкретного события (с таймаутом)
function event.pull(timeout, filter)
  local io = require("io")
  local start = io.uptime()
  while true do
    local sig = {coroutine.yield()}
    if #sig > 0 then
      if not filter or sig[1] == filter then
        return table.unpack(sig)
      end
    end
    if timeout and (io.uptime() - start >= timeout) then
      return nil
    end
  end
end

-- Вызывать этот метод в главном цикле приложения
function event.tick()
  local sig = {coroutine.yield()}
  if #sig > 0 then
    local name = sig[1]
    if event.handlers[name] then
      for _, callback in ipairs(event.handlers[name]) do
        callback(table.unpack(sig))
      end
    end
    return table.unpack(sig)
  end
  return nil
end

return event