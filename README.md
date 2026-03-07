# Atom OS
**Lightweight microkernel operating system for OpenComputers (Minecraft)**

🇷🇺 Read in Russian? [ЧИТАТЬ](https://github.com/KilDoomWise/AtomOS/blob/main/README_RU.md)

> Atom OS is a minimalist operating system designed with a focus on clean architecture, low resource consumption, and user-friendliness. It is based on a modular approach, strict privilege separation, and isolated environments rather than shared global states.

> When it comes to performance, there is a massive difference: while idling, OpenOS actively uses **350-400 KB** of RAM, whereas Atom uses only **135 KB**. This is the bare minimum, meaning Atom can run smoothly even on the weakest computer builds available in the mod!

## Architectural Features
* **Microkernel and Privilege Levels (Rings):** The system architecture is built on protection rings. 
  * **Ring-1:** System drivers (file system management, GPU, interrupts).
  * **Ring-2:** API libraries providing secure wrappers.
  * **Ring-3:** User sandbox. User programs have no direct access to the `component` table. All hardware calls pass through a protected bridge (`unit.lua`).
* **Modular Executing Shell (MES):** The command line is not hardcoded into the kernel. MES is a standard user application located at `/Apps/MES.app`. Shell commands (`ls`, `cd`, `open`, etc.) are loaded dynamically from `/Libraries/MES/`. You can easily write and use your own shell instead of the standard one.
* **App Encapsulation:** Programs are not scattered across the file system as single `.lua` scripts. They are stored and executed as `.app` package directories (e.g., `App.app/main.lua`), which keeps the system root clean.
* **Task Scheduler (APS):** Multitasking is implemented using asynchronous coroutines with priority level support. A built-in task manager (`htop`) allows you to monitor and terminate processes. 
  * *Note:* Multitasking is cooperative. If a program enters an infinite loop without calling `coroutine.yield()` (or handling system events), it will hang the entire system.
* **Ultimate Edit:** A built-in advanced code editor. It includes native Lua syntax highlighting, full mouse support (scrolling, clicking to move the cursor), hotkeys for search and navigation, and an optimized line-rendering cache.
* **Userspace:** Atom features a full-fledged user system with a "Root" account and individual user folders.

## Installation

1. Insert an **OpenOS (Operating System)** floppy disk (included by default in the mod).
2. An **Internet Card** is strictly required, as we will be installing Atom via the web.
3. Boot the computer and enter the command below (middle-click to paste in most terminals):


```
wget -q https://raw.githubusercontent.com/KilDoomWise/AtomOS/refs/heads/main/Installer/openos.lua /tmp/installer.lua && /tmp/installer.lua
```

4. Once the automated installer starts, follow the on-screen instructions.

Done!

> [!IMPORTANT]
> It is possible that the system contains bugs, including serious ones. If you encounter any, please report them in the **Issues** section! If you're interested in the project, feel free to try fixing the problem yourself.
