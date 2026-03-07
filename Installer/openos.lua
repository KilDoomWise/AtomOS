-- ═══════════════════════════════════════════════════════════════════════════
--  Atom OS  ·  Installer for OpenOS
--  https://github.com/KilDoomWise/AtomOS
-- ═══════════════════════════════════════════════════════════════════════════

local component = require("component")
local computer  = require("computer")
local unicode   = require("unicode")

-- ── Guards ──────────────────────────────────────────────────────────────────
if not component.isAvailable("internet") then
  io.write("Error: No Internet Card installed!\n"); return
end
if not component.isAvailable("gpu") then
  io.write("Error: No GPU!\n"); return
end

local gpu  = component.gpu
local inet = component.internet
local W, H = gpu.getResolution()

local BASE = "https://raw.githubusercontent.com/KilDoomWise/AtomOS/refs/heads/main/"

local FILES = {
  "init.lua",
  "System/kernel.lua",
  "System/aps.lua",
  "System/atfs.lua",
  "System/agpu.lua",
  "System/aio.lua",
  "System/envbuilder.lua",
  "System/unit.lua",
  "Apps/MES.app/main.lua",
  "Libraries/atomui.lua",
  "Libraries/auth.lua",
  "Libraries/event.lua",
  "Libraries/filesystem.lua",
  "Libraries/graphics.lua",
  "Libraries/internet.lua",
  "Libraries/io.lua",
  "Libraries/process.lua",
  "Libraries/unicode.lua",
  "Libraries/MES/cat.lua",
  "Libraries/MES/cd.lua",
  "Libraries/MES/clear.lua",
  "Libraries/MES/cp.lua",
  "Libraries/MES/echo.lua",
  "Libraries/MES/edit.lua",
  "Libraries/MES/fetch.lua",
  "Libraries/MES/hostname.lua",
  "Libraries/MES/htop.lua",
  "Libraries/MES/ls.lua",
  "Libraries/MES/lua.lua",
  "Libraries/MES/man.lua",
  "Libraries/MES/mkdir.lua",
  "Libraries/MES/mount.lua",
  "Libraries/MES/mv.lua",
  "Libraries/MES/open.lua",
  "Libraries/MES/passwd.lua",
  "Libraries/MES/pwd.lua",
  "Libraries/MES/reboot.lua",
  "Libraries/MES/rm.lua",
  "Libraries/MES/shutdown.lua",
  "Libraries/MES/su.lua",
  "Libraries/MES/tree.lua",
  "Libraries/MES/umount.lua",
  "Libraries/MES/useradd.lua",
  "Libraries/MES/userdel.lua",
  "Libraries/MES/wget.lua",
  "Libraries/MES/whoami.lua",
}

-- ── Colors ───────────────────────────────────────────────────────────────────
local C = {
  BG     = 0x000000,
  FG     = 0xCCCCCC,
  DIM    = 0x555555,
  OK     = 0x00CC66,
  ERR    = 0xFF4444,
  BLUE   = 0x00AAFF,
  BAR    = 0x0077AA,
  BAR_BG = 0x111111,
  SEL    = 0x001A33,
  HLINE  = 0x1A1A1A,
  HDR    = 0x0D1117,
}

-- ── TUI primitives ────────────────────────────────────────────────────────────
local function cls()
  gpu.setBackground(C.BG); gpu.setForeground(C.FG)
  gpu.fill(1, 1, W, H, " ")
end

local function at(x, y, s, fg, bg)
  if bg then gpu.setBackground(bg) end
  if fg then gpu.setForeground(fg) end
  gpu.set(x, y, s)
  gpu.setBackground(C.BG); gpu.setForeground(C.FG)
end

local function centerAt(y, s, fg, bg)
  local x = math.max(1, math.floor((W - unicode.len(s)) / 2) + 1)
  at(x, y, s, fg, bg)
end

local function hline(y, fg)
  gpu.setForeground(fg or C.HLINE)
  gpu.fill(1, y, W, 1, "─")
  gpu.setForeground(C.FG)
end

local function titleBar(s)
  gpu.setBackground(C.HDR); gpu.setForeground(C.BLUE)
  gpu.fill(1, 1, W, 1, " ")
  gpu.set(2, 1, "ATOM OS  ·  " .. s)
  gpu.setBackground(C.BG); gpu.setForeground(C.FG)
end

local function statusBar(s, fg)
  gpu.setBackground(C.HDR); gpu.setForeground(fg or C.DIM)
  gpu.fill(1, H, W, 1, " ")
  gpu.set(2, H, s)
  gpu.setBackground(C.BG); gpu.setForeground(C.FG)
end

local function progressBar(x, y, w, pct)
  local n = math.floor(w * math.max(0, math.min(1, pct)))
  gpu.setForeground(C.BAR)
  if n > 0 then gpu.set(x, y, string.rep("█", n)) end
  gpu.setForeground(C.BAR_BG)
  if n < w then gpu.set(x + n, y, string.rep("░", w - n)) end
  gpu.setForeground(C.FG)
end

local function readKey(timeout)
  local e, _, ch, code = computer.pullSignal(timeout or math.huge)
  if e == "key_down" then return ch, code end
  return nil, nil
end

local function sleep(t) computer.pullSignal(t) end

-- ── Splash ────────────────────────────────────────────────────────────────────
-- "ATOM OS" in ANSI Shadow font, light-to-dark gray gradient
local ART = {
  {" █████╗ ████████╗ ██████╗ ███╗   ███╗  ██████╗ ███████╗", 0xEEEEEE},
  {"██╔══██╗╚══██╔══╝██╔═══██╗████╗ ████║ ██╔═══██╗██╔════╝", 0xCCCCCC},
  {"███████║   ██║   ██║   ██║██╔████╔██║ ██║   ██║███████╗", 0xAAAAAA},
  {"██╔══██║   ██║   ██║   ██║██║╚██╔╝██║ ██║   ██║╚════██║", 0x888888},
  {"██║  ██║   ██║   ╚██████╔╝██║ ╚═╝ ██║ ╚██████╔╝███████║", 0x666666},
  {"╚═╝  ╚═╝   ╚═╝    ╚═════╝ ╚═╝     ╚═╝  ╚═════╝ ╚══════╝", 0x444444},
}

local function showSplash()
  cls()
  local sy = math.floor(H / 2) - math.floor(#ART / 2) - 2
  for i, row in ipairs(ART) do
    centerAt(sy + i - 1, row[1], row[2])
  end
  centerAt(sy + #ART + 1, "Installation Wizard  ·  v1.0", 0x444444)
  hline(H - 2)
  centerAt(H - 1, "[Enter]  Begin Installation      [Q]  Quit", C.DIM)
  while true do
    local ch, code = readKey()
    if code == 28 then return true end
    if ch == 113 or ch == 81 then return false end
  end
end

-- ── Drive selection ────────────────────────────────────────────────────────────
local function fmtSize(b)
  if not b or b == 0 then return "?" end
  if b >= 1048576 then return ("%.1f MB"):format(b / 1048576) end
  return ("%.0f KB"):format(b / 1024)
end

local function getDrives()
  local boot = computer.getBootAddress()
  local tmp  = computer.tmpAddress and computer.tmpAddress() or nil
  local list = {}
  for addr in component.list("filesystem") do
    if addr ~= boot and addr ~= tmp then
      local _, lbl   = pcall(component.invoke, addr, "getLabel")
      local _, total = pcall(component.invoke, addr, "spaceTotal")
      local _, free  = pcall(component.invoke, addr, "spaceAvailable")
      table.insert(list, {
        addr  = addr,
        short = addr:sub(1, 8),
        label = (type(lbl)   == "string" and lbl   ~= "") and lbl   or "unlabeled",
        total = type(total)  == "number"                  and total  or 0,
        free  = type(free)   == "number"                  and free   or 0,
      })
    end
  end
  return list
end

local function showDriveSelect()
  local drives = getDrives()
  if #drives == 0 then
    cls()
    centerAt(math.floor(H / 2) - 1, "No target drives found.", C.ERR)
    centerAt(math.floor(H / 2) + 1, "Connect a formatted Hard Drive and rerun the installer.", C.DIM)
    hline(H - 2)
    statusBar("[Any key]  Exit")
    readKey()
    return nil
  end

  local sel = 1
  local function draw()
    cls()
    titleBar("Select Target Drive")
    at(3, 3, "Choose the drive to install Atom OS onto:", C.FG)
    at(3, 4, "WARNING: All existing data will be erased!", C.ERR)
    hline(5)
    for i, d in ipairs(drives) do
      local y      = 6 + (i - 1) * 2
      local isSel  = (i == sel)
      local prefix = isSel and "  ►  " or "     "
      local fg     = isSel and 0xFFFFFF or C.DIM
      local bg     = isSel and C.SEL    or C.BG
      gpu.setBackground(bg); gpu.setForeground(fg)
      gpu.fill(2, y, W - 2, 1, " ")
      local line = string.format(
        "%s[%s...]  %-12s  %s total  /  %s free",
        prefix, d.short, d.label, fmtSize(d.total), fmtSize(d.free)
      )
      gpu.set(2, y, line)
      gpu.setBackground(C.BG); gpu.setForeground(C.FG)
    end
    hline(H - 2)
    statusBar("[↑↓]  Navigate      [Enter]  Select      [Q]  Quit")
  end

  draw()
  while true do
    local ch, code = readKey()
    if    code == 200 and sel > 1       then sel = sel - 1; draw()
    elseif code == 208 and sel < #drives then sel = sel + 1; draw()
    elseif code == 28                   then return drives[sel]
    elseif ch == 113 or ch == 81        then return nil
    end
  end
end

-- ── Confirmation ───────────────────────────────────────────────────────────────
local function showConfirm(d)
  cls()
  titleBar("Confirm Installation")
  local y = math.floor(H / 2) - 5
  centerAt(y,     "Ready to install  ATOM OS",                   C.FG)
  centerAt(y + 2, "Drive  :  " .. d.addr,                        C.BLUE)
  centerAt(y + 3, "Label  :  " .. d.label,                       C.DIM)
  centerAt(y + 4, "Size   :  " .. fmtSize(d.total),              C.DIM)
  centerAt(y + 5, "Files  :  " .. #FILES,                        C.DIM)
  centerAt(y + 7, "ALL DATA ON THIS DRIVE WILL BE ERASED!",      C.ERR)
  hline(H - 2)
  centerAt(H - 1, "[Enter]  Confirm & Install      [Q]  Cancel", C.DIM)
  while true do
    local ch, code = readKey()
    if code == 28 then return true end
    if ch == 113 or ch == 81 then return false end
  end
end

-- ── HTTP download ──────────────────────────────────────────────────────────────
local function httpGet(url)
  local ok, h = pcall(inet.request, url)
  if not ok or not h then return nil, tostring(h) end
  local buf  = {}
  local dead = computer.uptime() + 30
  while computer.uptime() < dead do
    local ok2, chunk = pcall(h.read, 65536)
    if ok2 then
      if chunk and #chunk > 0 then
        buf[#buf + 1] = chunk
      else
        break  -- EOF
      end
    else
      if tostring(chunk):find("not connected") then
        sleep(0.05)
      else
        break
      end
    end
  end
  pcall(h.close)
  local data = table.concat(buf)
  if #data == 0 then return nil, "empty response" end
  return data
end

-- ── Filesystem writer ──────────────────────────────────────────────────────────
local function ensureDirs(addr, path)
  local parts = {}
  for p in path:gmatch("[^/]+") do parts[#parts + 1] = p end
  table.remove(parts)  -- strip filename
  local dir = ""
  for _, p in ipairs(parts) do
    dir = dir .. "/" .. p
    pcall(component.invoke, addr, "makeDirectory", dir)
  end
end

local function writeFile(addr, path, data)
  ensureDirs(addr, path)
  local h = component.invoke(addr, "open", "/" .. path, "w")
  if not h then return false end
  component.invoke(addr, "write", h, data)
  component.invoke(addr, "close", h)
  return true
end

-- ── Install phase ──────────────────────────────────────────────────────────────
local SPIN = {"⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏"}
local spinI  = 1
local logBuf = {}

local function pushLog(s, fg)
  logBuf[#logBuf + 1] = {s = s, fg = fg or C.DIM}
  local LOG_Y   = 10
  local maxRows = H - 3 - LOG_Y
  while #logBuf > maxRows do table.remove(logBuf, 1) end
  gpu.setBackground(C.BG)
  gpu.fill(2, LOG_Y, W - 2, maxRows, " ")
  for i, ln in ipairs(logBuf) do
    gpu.setForeground(ln.fg)
    gpu.set(2, LOG_Y + i - 1, unicode.sub(ln.s, 1, W - 2))
  end
  gpu.setForeground(C.FG)
end

local function drawProgress(idx, file, spinning)
  local pct  = idx / #FILES
  local barW = W - 10
  at(3, 3, string.format("Installing Atom OS  ·  %d / %d files", idx, #FILES), C.DIM)
  progressBar(3, 5, barW, pct)
  at(barW + 4, 5, string.format(" %3d%%", math.floor(pct * 100)), C.DIM)
  gpu.setBackground(C.BG)
  gpu.fill(2, 7, W - 2, 1, " ")
  if spinning then
    local sp = SPIN[spinI]; spinI = (spinI % #SPIN) + 1
    at(2, 7, sp .. "  " .. file, C.BLUE)
  else
    at(2, 7, "✔  " .. file, C.OK)
  end
end

local function doInstall(drive)
  cls()
  titleBar("Installing...")
  hline(H - 2)

  for idx, file in ipairs(FILES) do
    drawProgress(idx - 1, file, true)

    -- Download with one retry
    local data, err
    for attempt = 1, 2 do
      data, err = httpGet(BASE .. file)
      if data then break end
      if attempt == 1 then
        statusBar("Retrying  " .. file .. "...", C.ERR)
        sleep(1.5)
      end
    end

    if not data then
      pushLog("  ✘  " .. file .. "  (" .. tostring(err) .. ")", C.ERR)
      statusBar("FATAL: download failed — " .. file, C.ERR)
      sleep(3)
      return false, "download failed: " .. file
    end

    if not writeFile(drive.addr, file, data) then
      pushLog("  ✘  write error: " .. file, C.ERR)
      statusBar("FATAL: write failed — " .. file, C.ERR)
      sleep(3)
      return false, "write failed: " .. file
    end

    drawProgress(idx, file, false)
    pushLog("  ✔  " .. file, 0x2A5C2A)
    statusBar("")
  end

  return true
end

-- ── Done ───────────────────────────────────────────────────────────────────────
local function showDone(addr)
  cls()
  local y = math.floor(H / 2) - 3
  centerAt(y,     "✔  Installation complete!", C.OK)
  centerAt(y + 2, "Atom OS has been written to:", C.DIM)
  centerAt(y + 3, addr, C.BLUE)

  local bootOk = pcall(computer.setBootAddress, addr)
  if bootOk then
    centerAt(y + 5, "Boot address updated.", C.DIM)
  else
    centerAt(y + 5, "Could not set boot address automatically.", C.DIM)
    centerAt(y + 6, "Set this drive as primary boot device manually.", C.DIM)
  end

  hline(H - 2)
  for i = 3, 1, -1 do
    statusBar("Rebooting in " .. i .. "s...", C.DIM)
    sleep(1)
  end
  computer.shutdown(true)
end

local function showError(msg)
  cls()
  local y = math.floor(H / 2) - 1
  centerAt(y,     "✘  Installation failed", C.ERR)
  centerAt(y + 2, msg or "Unknown error.", C.DIM)
  hline(H - 2)
  statusBar("[Any key]  Exit")
  readKey()
end

-- ── Entry point ────────────────────────────────────────────────────────────────
if not showSplash()       then return end
local drive = showDriveSelect()
if not drive              then return end
if not showConfirm(drive) then return end
local ok, err = doInstall(drive)
if ok then
  showDone(drive.addr)
else
  showError(err)
end
