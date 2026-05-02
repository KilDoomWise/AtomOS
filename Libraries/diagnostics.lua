local gpu = require("graphics")
local fs = require("filesystem")
local unicode = require("unicode")

local diagnostics = {}

local C = {
  red = 0xFF5555,
  redDark = 0xAA2222,
  yellow = 0xFFD75F,
  cyan = 0x55D7FF,
  gray = 0x888888,
  white = 0xFFFFFF
}

local function color(api, value)
  gpu.setForeground(value)
end

local function write(api, text, fg)
  color(api, fg or C.white)
  api.write(tostring(text or ""))
end

local function writeln(api, text, fg)
  write(api, tostring(text or "") .. "\n", fg)
end

local function cleanSource(source)
  source = tostring(source or "")
  if source:sub(1, 1) == "=" then source = source:sub(2) end
  local quoted = source:match('^%[string "(.*)"%]$')
  if quoted then source = quoted end
  return source
end

local function firstLine(text)
  return tostring(text or ""):match("([^\n]*)") or ""
end

local function parseLocation(trace)
  trace = tostring(trace or "")
  for line in (trace .. "\n"):gmatch("([^\n]*)\n") do
    line = line:gsub("^%s+", "")
    local source, num, msg = line:match("^([^:\n]+):(%d+):%s*(.*)$")
    if source and not source:match("^stack traceback") then
      msg = msg or ""
      if msg:match("^in function") or msg:match("^in main chunk") then msg = "" end
      return cleanSource(source), tonumber(num), msg
    end
  end
  return nil, nil, firstLine(trace)
end

local function readSourceLine(source, number)
  if not source or not number or source:sub(1, 1) ~= "/" then return nil end
  if not fs.exists(source) or fs.isDir(source) then return nil end

  local data = fs.readAll(source)
  if not data then return nil end

  local n = 1
  data = data:gsub("\r", "")
  for line in (data .. "\n"):gmatch("([^\n]*)\n") do
    if n == number then return line end
    n = n + 1
  end
  return nil
end

local function fit(text, width)
  text = tostring(text or "")
  if width <= 0 then return "" end
  if unicode.len(text) <= width then return text end
  if width <= 1 then return "~" end
  return unicode.sub(text, 1, width - 1) .. "~"
end

local function tracebackLines(trace)
  local out = {}
  local inStack = false
  for line in (tostring(trace or "") .. "\n"):gmatch("([^\n]*)\n") do
    if line:match("^stack traceback:") then
      inStack = true
      out[#out + 1] = "stack traceback:"
    elseif inStack then
      line = line:gsub("^%s+", "")
      if line ~= "" then out[#out + 1] = line end
    end
  end
  return out
end

function diagnostics.traceback(co, err)
  local message = tostring(err)
  if debug and debug.traceback then
    if type(co) == "thread" then
      local ok, trace = pcall(debug.traceback, co, message)
      if ok and trace then return trace end
    else
      local ok, trace = pcall(debug.traceback, message, 2)
      if ok and trace then return trace end
    end
  end
  return message
end

function diagnostics.make(err, co, label)
  if type(err) == "table" and (err.traceback or err.error) then
    return err
  end
  return {
    error = tostring(err),
    traceback = diagnostics.traceback(co, err),
    label = label
  }
end

function diagnostics.message(err, label)
  return {
    error = tostring(err),
    traceback = tostring(err),
    label = label
  }
end

function diagnostics.render(err, api, opts)
  if not api or not api.write then return end
  opts = opts or {}

  local item = diagnostics.make(err, nil, opts.label)
  local trace = item.traceback or tostring(item.error or err)
  local source, lineNo, parsedMsg = parseLocation(trace)
  local message = parsedMsg ~= "" and parsedMsg or firstLine(item.error or trace)
  local width = select(1, gpu.getResolution()) or 80
  local inner = math.max(20, width - 4)
  local title = tostring(opts.title or item.title or item.label or item.name or "Error Traceback")

  writeln(api, "")
  writeln(api, "+-- " .. fit(title, inner - 5) .. " " .. string.rep("-", math.max(0, inner - unicode.len(title) - 6)), C.red)

  if source and lineNo then
    write(api, "| at ", C.gray)
    write(api, source, C.cyan)
    write(api, ":" .. tostring(lineNo) .. "\n", C.yellow)
  end

  write(api, "| error: ", C.red)
  writeln(api, fit(message, inner - 9), C.white)

  local code = readSourceLine(source, lineNo)
  if code then
    writeln(api, "|", C.gray)
    local num = tostring(lineNo)
    local prefix = "| > " .. num .. " | "
    write(api, prefix, C.red)
    writeln(api, fit(code, width - unicode.len(prefix) - 1), C.red)
  end

  local stack = tracebackLines(trace)
  if #stack > 0 then
    writeln(api, "|", C.gray)
    writeln(api, "| Traceback", C.yellow)
    local limit = math.min(#stack, opts.maxFrames or 10)
    for i = 1, limit do
      writeln(api, "|   " .. fit(stack[i], inner - 4), i == 1 and C.gray or C.white)
    end
    if #stack > limit then
      writeln(api, "|   ... " .. tostring(#stack - limit) .. " more", C.gray)
    end
  end

  writeln(api, "+" .. string.rep("-", inner), C.redDark)
  color(api, C.white)
end

return diagnostics
