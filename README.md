# Atom OS
**A Lightweight Microkernel Operating System for OpenComputers (Minecraft)**

Atom OS is a minimalist operating system built from scratch with a focus on clean architecture, low resource footprint, and a user-friendly developer experience. It relies on a modular approach, strict privilege separation, and isolated execution environments instead of shared global states.

## Architectural Features

* **Microkernel & Ring Architecture:** The system is built on protection rings.
  * **Ring-1:** System drivers (filesystem management, GPU, interrupts).
  * **Ring-2:** API libraries providing secure wrappers.
  * **Ring-3:** User sandbox. User applications have zero direct access to the `component` API. All hardware calls are routed through a secure bridge (`unit.lua`).
* **Modular Executing Shell (MES):** The command-line interface is not hardcoded into the kernel. MES is a standard userland application located at `/Apps/MES.app`. Shell commands (`ls`, `cd`, `open`, etc.) are not hardcoded but loaded dynamically from `/Libraries/MES/`. You can easily write and run your own custom shell.
* **Application Encapsulation:** Programs are not scattered across the filesystem as flat `.lua` scripts. They are stored and executed as `.app` directory bundles (e.g., `App.app/main.lua`), keeping the root filesystem perfectly organized.
* **Task Scheduler (APS):** Multitasking is implemented using asynchronous coroutines with priority level support. A built-in task manager (`htop`) allows you to monitor and terminate processes.
  * *Note:* Multitasking is cooperative. If a program enters an infinite loop without calling `coroutine.yield()` (or handling system events), it will block the entire operating system.
* **Ultimate Edit:** A built-in, advanced code editor. It features native Lua syntax highlighting, full mouse support (scrolling, clicking to move the cursor), hotkeys for search and navigation, and an optimized row cache for fast, flicker-free rendering.
* **AtomUI Graphics Engine:** A core graphics library for building user interfaces. It includes mathematical compensation for the OpenComputers 1:2 pixel aspect ratio, allowing the rendering of geometrically accurate shapes (perfect circles instead of ovals) and supports semi-pixel rendering.

## Installation

**Note:** The automated installer (APM - Atom Package Manager) is currently under development and will be released in a few days. For now, installation requires manual file copying.

1. Format your computer's hard drive.
2. Create the root directories: `/System`, `/Libraries`, `/Apps`.
3. Place the `init.lua` bootloader in the root of the drive.
4. Distribute the system files (kernel, drivers, libraries, and MES.app) into their respective directories according to the repository structure.
5. Reboot the computer.