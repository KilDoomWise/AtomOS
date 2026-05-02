return function(args, api)
  local gpu = require("graphics")
  local unicode = require("unicode")

  local C = {
    title = 0x00FFFF,
    type = 0x79C0FF,
    method = 0xA5D6FF,
    arg = 0xFFD866,
    ret = 0x7EE787,
    desc = 0xE6EDF3,
    dim = 0x6E7681,
    border = 0x30363D,
    error = 0xFF6666,
    ok = 0x3FB950,
    fg = 0xFFFFFF
  }

  local width = select(1, gpu.getResolution()) or 80

  local function fg(color)
    gpu.setForeground(color or C.fg)
  end

  local function write(color, text)
    fg(color)
    api.write(tostring(text or ""))
    fg(C.fg)
  end

  local function println(color, text)
    write(color, text)
    api.write("\n")
  end

  local function short(addr)
    return addr and addr:sub(1, 8) or "unknown"
  end

  local function trim(s)
    return tostring(s or ""):match("^%s*(.-)%s*$")
  end

  local function wrapText(text, maxWidth)
    text = trim((text or ""):gsub("\r", " "):gsub("\n", " "))
    if text == "" then return {""} end

    local lines, line = {}, ""
    for word in text:gmatch("%S+") do
      if unicode.len(line) == 0 then
        line = word
      elseif unicode.len(line) + 1 + unicode.len(word) <= maxWidth then
        line = line .. " " .. word
      else
        lines[#lines + 1] = line
        line = word
      end
    end
    if line ~= "" then lines[#lines + 1] = line end
    return lines
  end

  local function parseDoc(methodName, doc)
    if not doc or doc == "" then
      return nil, {}, nil, "No documentation exported by this component."
    end

    doc = tostring(doc):gsub("\r", "")
    local first, rest = doc:match("^([^\n]*)\n?(.*)$")
    first = trim(first)
    rest = trim(rest)

    local signature, desc = nil, doc
    if first:find("%(") or first:find(methodName, 1, true) then
      signature = first
      desc = rest ~= "" and rest or ""
    end

    if not signature then
      local before, after = doc:match("^(.-)%s*%-%-%s*(.+)$")
      if before and before:find("%(") then
        signature = trim(before)
        desc = trim(after)
      end
    end

    if signature and desc == "" then
      local before, after = signature:match("^(.-)%s*%-%-%s*(.+)$")
      if before and after then
        signature = trim(before)
        desc = trim(after)
      end
    end

    local argText = signature and signature:match("%((.-)%)") or nil
    local retText = signature and (signature:match("%)%s*:%s*(.+)$") or signature:match("%)%s*%-%>%s*(.+)$")) or nil
    local parsedArgs = {}

    if argText and trim(argText) ~= "" then
      for part in argText:gmatch("[^,]+") do
        parsedArgs[#parsedArgs + 1] = trim(part)
      end
    end

    desc = trim(desc)
    if desc == "" and not signature then desc = trim(doc) end
    if desc == "" then desc = "No description." end

    return signature, parsedArgs, retText and trim(retText) or nil, desc
  end

  local function box(prefix, rows)
    local maxText = math.max(24, math.min(68, width - unicode.len(prefix) - 6))
    write(C.border, prefix .. "╭" .. string.rep("─", maxText + 2) .. "╮\n")

    for _, row in ipairs(rows) do
      local label, text, color = row[1], row[2], row[3] or C.desc
      local labelText = label and (label .. ": ") or ""
      local labelLen = unicode.len(labelText)
      local wrapped = wrapText(text, math.max(8, maxText - labelLen))

      for i, line in ipairs(wrapped) do
        local left = (i == 1) and labelText or string.rep(" ", labelLen)
        local content = left .. line
        local pad = maxText - unicode.len(content)
        if pad < 0 then pad = 0 end

        write(C.border, prefix .. "│ ")
        if i == 1 and label then write(C.dim, labelText) else api.write(string.rep(" ", labelLen)) end
        write(color, line)
        api.write(string.rep(" ", pad))
        write(C.border, " │\n")
      end
    end

    write(C.border, prefix .. "╰" .. string.rep("─", maxText + 2) .. "╯\n")
  end

  local function components()
    local list, err = unit.call("aio", "components")
    if not list then return nil, err end
    return list
  end

  local function printUsage()
    println(C.title, "Atom Component Docs")
    println(C.dim, "Usage:")
    println(C.desc, "  doc                         list installed components")
    println(C.desc, "  doc <type|address>          show component methods")
    println(C.desc, "  doc <type|address>.<method> show one method")
    println(C.desc, "  doc <type|address> <method> show one method")
    api.write("\n")
  end

  local function listComponents()
    local list, err = components()
    if not list then
      println(C.error, "doc: " .. tostring(err))
      return
    end

    printUsage()
    println(C.title, "Components")
    for i, c in ipairs(list) do
      local last = i == #list
      write(C.dim, last and "└─ " or "├─ ")
      write(C.type, c.type or "unknown")
      write(C.dim, "  [" .. short(c.addr) .. "]")
      if c.slot then write(C.dim, " slot " .. tostring(c.slot)) end
      api.write("\n")
    end
  end

  local function resolveComponent(query)
    local list, err = components()
    if not list then return nil, nil, err end

    local q = query:lower()
    local typeMatches, prefixMatches = {}, {}

    for _, c in ipairs(list) do
      local ctype = tostring(c.type or ""):lower()
      local addr = tostring(c.addr or ""):lower()

      if addr == q then
        return c, {c}
      end
      if ctype == q then
        typeMatches[#typeMatches + 1] = c
      elseif ctype:sub(1, #q) == q or addr:sub(1, #q) == q then
        prefixMatches[#prefixMatches + 1] = c
      end
    end

    if #typeMatches > 0 then return typeMatches[1], typeMatches end
    if #prefixMatches == 1 then return prefixMatches[1], prefixMatches end
    if #prefixMatches > 1 then return nil, prefixMatches, "ambiguous component: " .. query end
    return nil, nil, "component not found: " .. query
  end

  local function getMethods(comp)
    local methods, err = unit.call("aio", "methods", comp.addr)
    if not methods then return nil, err end
    return methods
  end

  local function findMethod(methods, query)
    local q = query:lower()
    local matches = {}
    for _, m in ipairs(methods) do
      local name = m.name or ""
      local lower = name:lower()
      if lower == q then return m, {m} end
      if lower:sub(1, #q) == q then matches[#matches + 1] = m end
    end
    if #matches == 1 then return matches[1], matches end
    return nil, matches
  end

  local function showMethod(comp, method, prefix, last)
    local connector = last and "└─ " or "├─ "
    local childPrefix = prefix .. (last and "   " or "│  ")

    write(C.dim, prefix .. connector)
    write(C.method, method.name)
    if method.direct then write(C.ok, "  direct") end
    api.write("\n")

    local doc = unit.call("aio", "doc", comp.addr, method.name)
    local signature, parsedArgs, returns, desc = parseDoc(method.name, doc)
    local rows = {}

    if signature then rows[#rows + 1] = {"sig", signature, C.method} end
    if #parsedArgs > 0 then
      rows[#rows + 1] = {"args", table.concat(parsedArgs, ", "), C.arg}
    else
      rows[#rows + 1] = {"args", "none documented", C.dim}
    end
    if returns then rows[#rows + 1] = {"returns", returns, C.ret} end
    rows[#rows + 1] = {"desc", desc, C.desc}

    box(childPrefix, rows)
  end

  local target = args[1]
  local methodQuery = args[2]

  if target and target:find(".", 1, true) and not methodQuery then
    local t, m = target:match("^([^%.]+)%.(.+)$")
    if t and m then
      target, methodQuery = t, m
    end
  end

  if not target or target == "list" then
    listComponents()
    return
  end

  local comp, matches, err = resolveComponent(target)
  if not comp then
    println(C.error, "doc: " .. tostring(err))
    if matches and #matches > 0 then
      println(C.dim, "Matches:")
      for _, c in ipairs(matches) do
        println(C.desc, "  " .. tostring(c.type) .. " [" .. short(c.addr) .. "]")
      end
    end
    return
  end

  local methods, merr = getMethods(comp)
  if not methods then
    println(C.error, "doc: " .. tostring(merr))
    return
  end

  write(C.title, "Component ")
  write(C.type, comp.type or "unknown")
  write(C.dim, " [" .. short(comp.addr) .. "]")
  if comp.slot then write(C.dim, " slot " .. tostring(comp.slot)) end
  api.write("\n")

  if matches and #matches > 1 then
    println(C.dim, "Showing first matching component; methods are usually identical per type.")
  end
  api.write("\n")

  if methodQuery then
    local method, mmatches = findMethod(methods, methodQuery)
    if not method then
      println(C.error, "doc: method not found: " .. methodQuery)
      if #mmatches > 0 then
        println(C.dim, "Method matches:")
        for _, m in ipairs(mmatches) do println(C.desc, "  " .. m.name) end
      end
      return
    end

    showMethod(comp, method, "", true)
    return
  end

  println(C.title, "Methods")
  for i, method in ipairs(methods) do
    showMethod(comp, method, "", i == #methods)
  end
end
