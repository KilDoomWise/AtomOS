return function()
  local theme = {}

  theme.color = {
    bg        = 0x0B0C0E,
    bg2       = 0x141619,
    window    = 0x202124,
    window2   = 0x27292D,
    panel     = 0x17191D,
    field     = 0x101114,
    taskbar   = 0x1E1E1E,
    accent    = 0x2D2D2D,
    accent2   = 0x363636,
    active    = 0x38414A,
    selected  = 0x45515C,
    text      = 0xFFFFFF,
    subtext   = 0x8A8A8A,
    muted     = 0x666666,
    divider   = 0x3A3A3A,
    shadow    = 0x070707,
    ok        = 0x68D391,
    warn      = 0xF6C177,
    danger    = 0xF87171,
    info      = 0x7DD3FC
  }

  theme.layout = {
    maxW = 160,
    maxH = 50,
    topbarH = 1,
    taskbarH = 3,
    menuW = 24,
    menuPadX = 2,
    popupPad = 1,
    iconW = 14,
    iconH = 5,
    iconGlyphW = 6,
    iconGlyphH = 3,
    launcherCellW = 16,
    launcherCellH = 6,
    winMinW = 34,
    winMinH = 10
  }

  theme.symbol = {
    logo = "✦",
    power = "⏻",
    close = "×",
    min = "–",
    up = "▴",
    down = "▾",
    dot = "•",
    folder = "▣",
    gear = "⚙",
    app = "◆",
    file = "◇",
    edit = "✎",
    calc = "∑",
    task = "≋",
    terminal = "▰",
    check = "✓"
  }

  return theme
end
