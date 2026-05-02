return function(state)
  local syntax = {}
  local unicode = require("unicode")

  local C = {
    BG = 0x0D1117, CUR_BG = 0x161B22, FG = 0xE6EDF3, BAR_BG = 0x161B22,
    KEY = 0xFFFFFF, HINT = 0x79C0FF, DIM = 0x8B949E, OK = 0x3FB950,
    GT_DIM = 0x3D444D, GT_CUR = 0x8B949E, KW = 0xFF7B72, BUILTIN = 0xD2A8FF,
    STR = 0xA5D6FF, CMT = 0x6E7681, NUM = 0xE8B87D, SEL_BG = 0x264F78,
    FIND_BG = 0x3A3320, FIND_CUR_BG = 0x5A4518,
    FIND_SCROLL = 0xD29922, SCROLL_MARK = 0x6E7681, STICKY_BG = 0x1F242D,
    INDENT_GUIDE = 0x252A31, MENU_BG = 0x111820, MENU_SEL_BG = 0x264F78,
    NEW_BG = 0x202A35, POPUP_BG = 0x101820, DIRTY = 0xD29922,
    INPUT_BG = 0x1A2430, INPUT_FOCUS_BG = 0x263447
  }
  syntax.C = C
  syntax.cache = {}
  syntax.cacheN = 0

  local LUA_KW = {
    ["local"]=1, ["function"]=1, ["return"]=1, ["if"]=1, ["then"]=1,
    ["else"]=1,  ["elseif"]=1,   ["end"]=1,    ["for"]=1, ["while"]=1,
    ["do"]=1,    ["and"]=1,      ["or"]=1,     ["not"]=1, ["nil"]=1,
    ["true"]=1,  ["false"]=1,    ["in"]=1,     ["repeat"]=1, ["until"]=1,
    ["break"]=1,
  }
  local LUA_BI = {
    ["require"]=1, ["print"]=1,  ["math"]=1,   ["table"]=1,  ["string"]=1,
    ["io"]=1,      ["gpu"]=1,    ["pcall"]=1,  ["xpcall"]=1, ["error"]=1,
    ["assert"]=1,  ["pairs"]=1,  ["ipairs"]=1, ["type"]=1,   ["tostring"]=1,
    ["tonumber"]=1,["select"]=1, ["next"]=1,   ["load"]=1,   ["unit"]=1,
    ["unicode"]=1, ["coroutine"]=1,
  }

  function syntax.highlight(line)
    if syntax.cache[line] then return syntax.cache[line] end
    local segs = {}
    local len = unicode.len(line)
    local i = 1
    while i <= len do
      local c = unicode.sub(line, i, i)
      if unicode.sub(line, i, i + 1) == "--" then
        table.insert(segs, {unicode.sub(line, i, len), C.CMT})
        break
      elseif c == '"' or c == "'" then
        local q = c
        local j = i + 1
        while j <= len and unicode.sub(line, j, j) ~= q do
          if unicode.sub(line, j, j) == "\\" then j = j + 2 else j = j + 1 end
        end
        table.insert(segs, {unicode.sub(line, i, j), C.STR})
        i = j + 1
      elseif c:match("%d") then
        local j = i
        while j <= len and unicode.sub(line, j, j):match("[%d%.xXa-fA-F]") do j = j + 1 end
        table.insert(segs, {unicode.sub(line, i, j - 1), C.NUM})
        i = j
      elseif c:match("[%a_]") then
        local j = i
        while j <= len and unicode.sub(line, j, j):match("[%w_]") do j = j + 1 end
        local word = unicode.sub(line, i, j - 1)
        local col = LUA_KW[word] and C.KW or LUA_BI[word] and C.BUILTIN or C.FG
        table.insert(segs, {word, col})
        i = j
      else
        local last = segs[#segs]
        if last and last[2] == C.FG then
          last[1] = last[1] .. c
        else
          table.insert(segs, {c, C.FG})
        end
        i = i + 1
      end
    end
    syntax.cache[line] = segs
    syntax.cacheN = syntax.cacheN + 1
    if syntax.cacheN > 600 then syntax.cache = {}; syntax.cacheN = 0 end
    return segs
  end

  return syntax
end
