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

  "System/agpu.lua",
  "System/aio.lua",
  "System/aps.lua",
  "System/atfs.lua",
  "System/atomui.lua",
  "System/envbuilder.lua",
  "System/kernel.lua",
  "System/unit.lua",

  "Apps/AtomUI.app/buffer.lua",
  "Apps/AtomUI.app/desktop.lua",
  "Apps/AtomUI.app/launcher.lua",
  "Apps/AtomUI.app/main.lua",
  "Apps/AtomUI.app/theme.lua",
  "Apps/AtomUI.app/widgets.lua",
  "Apps/AtomUI.app/windows.lua",
  "Apps/Calculator.app/atomapp.lua",
  "Apps/Edit.app/core.lua",
  "Apps/Edit.app/data/settings.lua",
  "Apps/Edit.app/input.lua",
  "Apps/Edit.app/main.lua",
  "Apps/Edit.app/syntax.lua",
  "Apps/Edit.app/ui.lua",
  "Apps/Files.app/atomapp.lua",
  "Apps/MES.app/main.lua",
  "Apps/Settings.app/atomapp.lua",
  "Apps/TaskManager.app/atomapp.lua",
  "Apps/Terminal.app/atomapp.lua",
  "Apps/TextEdit.app/atomapp.lua",

  "Libraries/applauncher.lua",
  "Libraries/atomui.lua",
  "Libraries/atomui_node.lua",
  "Libraries/auth.lua",
  "Libraries/diagnostics.lua",
  "Libraries/doublebuffer.lua",
  "Libraries/event.lua",
  "Libraries/filesystem.lua",
  "Libraries/graphics.lua",
  "Libraries/internet.lua",
  "Libraries/io.lua",
  "Libraries/process.lua",
  "Libraries/unicode.lua",

  "Libraries/MES/atomui.lua",
  "Libraries/MES/cat.lua",
  "Libraries/MES/cd.lua",
  "Libraries/MES/clear.lua",
  "Libraries/MES/cp.lua",
  "Libraries/MES/doc.lua",
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
  "Libraries/MES/run.lua",
  "Libraries/MES/shutdown.lua",
  "Libraries/MES/su.lua",
  "Libraries/MES/tree.lua",
  "Libraries/MES/umount.lua",
  "Libraries/MES/useradd.lua",
  "Libraries/MES/userdel.lua",
  "Libraries/MES/wget.lua",
  "Libraries/MES/whoami.lua",
}

local DEFAULT_FILES = {
  ["etc/atomui.cfg"] = "autostart=true\nheight=50\nwidth=160\n",
  ["etc/hostname"] = "atom\n",
  ["etc/passwd"] = "# AtomOS passwd\nroot::0:/root\n",
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

-- ── Core FS & Network Logic ────────────────────────────────────────────────────
local function formatDrive(addr)
  local proxy = component.proxy(addr)
  local function joinPath(a, b)
    if a == "/" then return "/" .. b end
    return a .. "/" .. b
  end
  local function removeTree(path)
    local ok, list = pcall(proxy.list, path)
    if ok and list then
      for _, entry in ipairs(list) do
        removeTree(joinPath(path, tostring(entry):gsub("/$", "")))
      end
    end
    if path ~= "/" then pcall(proxy.remove, path) end
  end
  local ok, list = pcall(proxy.list, "/")
  if ok and list then
    for _, file in ipairs(list) do
      removeTree("/" .. tostring(file):gsub("/$", ""))
    end
  end
end

local function ensureDirs(addr, path)
  local parts = {}
  for p in path:gmatch("[^/]+") do parts[#parts + 1] = p end
  table.remove(parts)
  local dir = ""
  for _, p in ipairs(parts) do
    dir = dir .. "/" .. p
    pcall(component.invoke, addr, "makeDirectory", dir)
  end
end

local function readRequest(req)
  local chunks, total = {}, 0
  local deadline = computer.uptime() + 45
  while true do
    local ok, chunk = pcall(req.read, math.huge)
    if ok then
      if chunk == nil then break end
      if #chunk > 0 then
        chunks[#chunks + 1] = chunk
        total = total + #chunk
        deadline = computer.uptime() + 15
      else
        sleep(0.05)
      end
    else
      local msg = tostring(chunk)
      if msg:find("not connected", 1, true) and computer.uptime() < deadline then
        sleep(0.05)
      else
        return nil, msg
      end
    end
    if computer.uptime() > deadline then return nil, "network timeout" end
  end

  local data = table.concat(chunks)
  if total <= 0 then return nil, "empty response" end
  if data:match("^404:%s*Not Found") then return nil, "not found in repository" end
  return data
end

local function download(url)
  local lastErr = "unknown error"
  for attempt = 1, 3 do
    local ok, req, reason = pcall(inet.request, url)
    if ok and req then
      local data, err = readRequest(req)
      pcall(req.close)
      if data then return true, data end
      lastErr = err or lastErr
    else
      lastErr = tostring(ok and reason or req)
    end
    sleep(0.35 * attempt)
  end
  return false, lastErr
end

local function downloadAndWrite(addr, url, path)
  -- Создаем папки
  local parts = {}
  for p in path:gmatch("[^/]+") do parts[#parts + 1] = p end
  table.remove(parts)
  local dir = ""
  for _, p in ipairs(parts) do
    dir = dir .. "/" .. p
    component.invoke(addr, "makeDirectory", dir)
  end

  -- Открываем файл
  local handle, err = component.invoke(addr, "open", "/" .. path, "w")
  if not handle then return false, "open err: " .. tostring(err) end

  -- Дергаем инет
  local ok, req = pcall(inet.request, url)
  if not ok or not req then
    component.invoke(addr, "close", handle)
    return false, "req err: " .. tostring(req)
  end

  -- Стримим данные на диск
  while true do
    local rok, chunk = pcall(req.read, math.huge)
    if rok then
      if chunk == nil then break
      elseif #chunk > 0 then
        component.invoke(addr, "write", handle, chunk)
      else
        sleep(0.05)
      end
    else
      if tostring(chunk):find("not connected") then
        sleep(0.05)
      else
        break
      end
    end
  end

  pcall(req.close)
  component.invoke(addr, "close", handle)
  return true
end

local function downloadAndWriteSafe(addr, url, path)
  local ok, data = download(url)
  if not ok then return false, tostring(data) end

  ensureDirs(addr, path)

  local handle, err = component.invoke(addr, "open", "/" .. path, "w")
  if not handle then return false, "open err: " .. tostring(err) end

  for i = 1, #data, 8192 do
    local written, writeErr = component.invoke(addr, "write", handle, data:sub(i, i + 8191))
    if not written then
      component.invoke(addr, "close", handle)
      return false, "write err: " .. tostring(writeErr)
    end
  end

  component.invoke(addr, "close", handle)
  return true
end

local function writeText(addr, path, data)
  ensureDirs(addr, path)
  local handle, err = component.invoke(addr, "open", "/" .. path, "w")
  if not handle then return false, "open err: " .. tostring(err) end
  local written, writeErr = component.invoke(addr, "write", handle, data or "")
  component.invoke(addr, "close", handle)
  if not written then return false, "write err: " .. tostring(writeErr) end
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

  -- Форматирование
  statusBar("Formatting drive...", C.DIM)
  pushLog("  ►  Formatting drive " .. drive.short .. "...", C.BLUE)
  formatDrive(drive.addr)
  pushLog("  ✔  Drive formatted completely", C.OK)
  sleep(0.5)

  -- Установка файлов
  for idx, file in ipairs(FILES) do
    drawProgress(idx - 1, file, true)

    local ok, err = downloadAndWriteSafe(drive.addr, BASE .. file, file)

    if not ok then
      pushLog("  ✘  " .. file .. "  (" .. tostring(err) .. ")", C.ERR)
      statusBar("FATAL: " .. tostring(err), C.ERR)
      sleep(4)
      return false, "failed: " .. file .. " (" .. tostring(err) .. ")"
    end

    drawProgress(idx, file, false)
    pushLog("  ✔  " .. file, 0x2A5C2A)
    statusBar("")
  end

  for path, data in pairs(DEFAULT_FILES) do
    local ok, err = writeText(drive.addr, path, data)
    if not ok then
      pushLog("  ✘  " .. path .. "  (" .. tostring(err) .. ")", C.ERR)
      return false, "failed: " .. path .. " (" .. tostring(err) .. ")"
    end
    pushLog("  ✔  " .. path, 0x2A5C2A)
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
