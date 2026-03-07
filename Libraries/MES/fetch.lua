return function(args, api)
  local gpu = require("graphics")
  local sys = require("io")

  local function fmtTime(s)
    s = math.floor(s)
    local d  = math.floor(s / 86400); s = s % 86400
    local hr = math.floor(s / 3600);  s = s % 3600
    local mn = math.floor(s / 60);    s = s % 60
    if d  > 0 then return ("%dd %dh %dm"):format(d, hr, mn) end
    if hr > 0 then return ("%dh %dm %ds"):format(hr, mn, s) end
    return ("%dm %ds"):format(mn, s)
  end

  local function fmtMem(b)
    if b >= 1048576 then return ("%.1f MB"):format(b / 1048576) end
    if b >= 1024    then return ("%.0f KB"):format(b / 1024) end
    return b .. " B"
  end

  local scrW, scrH = gpu.getResolution()
  local maxW, maxH = gpu.maxResolution()
  local depth      = gpu.getDepth() or 0

  local depthStr = ({
    [1] = "1-bit (Monochrome)",
    [4] = "4-bit (16 colors)",
    [8] = "8-bit (256 colors)",
  })[depth] or (depth .. "-bit")

  local total  = sys.totalMemory()    or 0
  local free   = sys.freeMemory()     or 0
  local used   = total - free
  local nComp  = sys.componentCount() or 0
  local uptime = sys.uptime()         or 0
  local energy    = sys.energy()
  local maxEnergy = sys.maxEnergy()

  local mls    = unit.call("atfs", "listMounts") or {}
  local mParts = {}
  for _, m in ipairs(mls) do table.insert(mParts, m.point) end
  local mountStr = #mParts > 0 and table.concat(mParts, "  ") or "none"

  local userName = api.getUser().name
  local hostName = api.getHostname()

  local INFO = {
    { "OS",      "Atom OS  v1.0" },
    { "Kernel",  "Microkernel / Ring-3 Sandbox" },
    { "Shell",   "MES  (Modular Executing Shell)" },
    { "Uptime",  fmtTime(uptime) },
    { "Memory",  fmtMem(used) .. " / " .. fmtMem(total) },
    { "Screen",  ("%dx%d  (max %dx%d)"):format(scrW, scrH, maxW or scrW, maxH or scrH) },
    { "Colors",  depthStr },
    { "Devices", nComp .. " components" },
    { "Mounts",  mountStr },
  }
  if energy and maxEnergy and maxEnergy > 0 then
    table.insert(INFO, { "Power", ("%.0f / %.0f RF  (%.0f%%)"):format(
      energy, maxEnergy, energy / maxEnergy * 100) })
  end

  local lblW = 0
  for _, row in ipairs(INFO) do
    if #row[1] > lblW then lblW = #row[1] end
  end

  local C = {
    USER  = 0x00FF99,
    AT    = 0x555566,
    HOST  = 0x00CCFF,
    LINE  = 0x2A2A4A,
    LABEL = 0x79C0FF,
    COLON = 0x444466,
    VALUE = 0xE6EDF3,
  }

  local function writeFg(color, text)
    gpu.setForeground(color)
    api.write(text)
  end

  local headerStr = userName .. "@" .. hostName
  local sepW = math.max(#headerStr, lblW + 3 + 20)

  api.write("\n")

  writeFg(C.USER, userName)
  writeFg(C.AT,   "@")
  writeFg(C.HOST, hostName)
  api.write("\n")

  writeFg(C.LINE, string.rep("─", sepW))
  api.write("\n")

  for _, row in ipairs(INFO) do
    local label = row[1]
    local value = row[2]
    local pad = string.rep(" ", lblW - #label)
    writeFg(C.LABEL, label .. pad)
    writeFg(C.COLON, " : ")
    writeFg(C.VALUE, value)
    api.write("\n")
  end

  api.write("\n")

  local palette = {
    0xFF5555, 0xFF9944, 0xFFFF55, 0x55FF55,
    0x55FFFF, 0x5555FF, 0xFF55FF, 0xCCCCCC,
  }
  for _, col in ipairs(palette) do
    gpu.setBackground(col)
    api.write("  ")
  end
  gpu.setBackground(0x000000)
  api.write("\n\n")

  gpu.setForeground(0xFFFFFF)
end