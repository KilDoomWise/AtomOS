return function(args, api)
  local gpu = require("graphics")
  local man = {
    ls = "List directory contents. Usage: ls [path]",
    cd = "Change current directory. Usage: cd <path>",
    cat = "Concatenate and print files. Usage: cat <file>",
    doc = "Show OpenComputers component docs. Usage: doc <component> [method]",
    echo = "Display a line of text. Usage: echo [text]",
    edit = "Edit a file. Usage: edit <file>",
    mkdir = "Create a directory. Usage: mkdir <path>",
    rm = "Remove files or directories. Usage: rm <path>",
    cp = "Copy files. Usage: cp <src> <dest>",
    mv = "Move/Rename files. Usage: mv <src> <dest>",
    pwd = "Print working directory. Usage: pwd",
    clear = "Clear the terminal screen. Usage: clear",
    reboot = "Reboot the system. Usage: reboot",
    shutdown = "Shutdown the system. Usage: shutdown",
    wget = "Download file from URL. Usage: wget <url> <filename>",
    open = "Launch an .app package as a background process. Usage: open <app>",
    run = "Run an .app package in foreground. Usage: run <name|path.app> [args]",
    process = "List or kill processes. Usage: htop / kill <pid>",
    lua = "Start Lua REPL. Usage: lua"
  }

  local topic = args[1]
  if not topic then
    api.print("Atom OS Manual")
    api.print("Usage: man <command>")
    api.print("Available commands:")
    local cmds = ""
    local i = 0
    for k, v in pairs(man) do
      cmds = cmds .. k .. "  "
      i = i + 1
      if i % 6 == 0 then cmds = cmds .. "\n" end
    end
    api.print(cmds)
  else
    if man[topic] then
      gpu.setForeground(0x00FF00)
      api.print("MANUAL ENTRY: " .. topic)
      gpu.setForeground(0xFFFFFF)
      api.print(man[topic])
    else
      api.print("No manual entry for " .. topic)
    end
  end
end
