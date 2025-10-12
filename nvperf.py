#!/usr/bin/env python3
import os
import sys
import signal
import curses
import inspect
import subprocess
import psutil

devenv = os.environ.copy()
devenv.update({
    "__GL_SYNC_TO_VBLANK": "0",
    "vblank_mode": "0",
    "__GL_DEBUG_BYPASS_ASSERT": "c",
    "PIP_BREAK_SYSTEM_PACKAGES": "1",
    "NVM_GTLAPI_USER": "wanliz",
    "NVM_GTLAPI_TOKEN": "eyJhbGciOiJIUzI1NiJ9.eyJpZCI6IjNlODVjZDU4LTM2YWUtNGZkMS1iNzZkLTZkZmZhNDg2ZjIzYSIsInNlY3JldCI6IkpuMjN0RkJuNTVMc3JFOWZIZW9tWk56a1Qvc0hpZVoxTW9LYnVTSkxXZk09In0.NzUoZbUUPQbcwFooMEhG4O0nWjYJPjBiBi78nGkhUAQ",
    "P4PORT": "p4proxy-sc.nvidia.com:2006",
    "P4USER": "wanliz",
    "P4CLIENT": "wanliz_sw_linux",
    "P4IGNORE": "~/.p4ignore"
})

class CMD_info:
    def __str__(self):
        return "Query GPU list and driver info"
    
    def run(self):
        os.system('bash -lci "nvidia-smi --query-gpu=name,driver_version,pci.bus_id,memory.total --format=csv"'); print()
        os.system('bash -lci "modinfo nvidia -F version || cat /proc/driver/nvidia/version"'); print()
        for key in ["DISPLAY", "WAYLAND_DISPLAY", "XDG_SESSION_TYPE", "LD_PRELOAD", "LD_LIBRARY_PATH"] + sorted([k for k in os.environ if k.startswith("__GL_") or k.startswith("VK_")]):
            value = os.environ.get(key)
            print(f"{key}={value}") if value is not None else None 
        print()
        os.system('bash -lci "glxinfo -B | grep \"renderer string\""'); print()

class CMD_config:
    def __str__(self):
        return "Configure test environment for NVIDIA GPU"
    
    def run(self):
        if not any(p.mountpoint == "/mnt/linuxqa" for p in psutil.disk_partitions(all=True)):
            subprocess.run("sudo mkdir -p /mnt/linuxqa", shell=True, check=True)
            subprocess.run("sudo mount linuxqa.nvidia.com:/storage/people /mnt/linuxqa", shell=True, check=True)
            print("Mounted /mnt/linuxqa")

def draw_menu(stdscr, cmds):
    curses.curs_set(0)
    stdscr.keypad(True)
    idx, top = 0, 0
    while True:
        h, w = stdscr.getmaxyx()
        view = max(1, h - 2)
        top = max(min(top, idx), idx - view + 1)
        stdscr.erase()
        stdscr.addnstr(0, 0, "Select a command [↑/↓] to move, [Enter] to run, [Esc] to quit, [Esc] to quit", w - 1)
        for i, cmd in enumerate(cmds[top:top + view], start=2):
            j = top + (i - 2)
            name = cmd.__class__.__name__[4:]
            line = f"{j+1:2d}. {name} — {cmd}"
            stdscr.addnstr(i, 0, line, w - 1, curses.A_REVERSE if j == idx else 0)
        stdscr.refresh()

        key = stdscr.getch()
        if key == 27:
            break
        idx = (idx - (key == curses.KEY_UP) + (key == curses.KEY_DOWN)) % len(cmds)
        if key in (10, 13, curses.KEY_ENTER):
            curses.def_prog_mode()
            curses.endwin()
            cmds[idx].run()
            input("\nPress [Enter] to return...")
            curses.reset_prog_mode()


if __name__ == "__main__":
    mods = sys.modules[__name__]
    cmds = []
    for n, kls in inspect.getmembers(mods, inspect.isclass):
        if kls.__module__ == __name__ and n.startswith("CMD_"):
            cmds.append(kls())
    cmds.sort(key=lambda x: x.__class__.__name__)
    curses.wrapper(lambda stdscr: draw_menu(stdscr, cmds))