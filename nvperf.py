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

def run_cmd(args, cwd=f"{os.getcwd()}", newline=False):
    try:
        if isinstance(args, list):
            subprocess.run(args, check=True, cwd=cwd)
        elif isinstance(args, str):
            subprocess.run(["/bin/bash", "-lci", args], check=True, cwd=cwd)
        else:
            raise RuntimeError("")
        if newline:
            print("")
    except (subprocess.CalledProcessError, FileNotFoundError, RuntimeError):
        exit(1)

class CMD_info:
    def __str__(self):
        return "Get GPU HW and driver info"
    
    def run(self):
        run_cmd("nvidia-smi --query-gpu=name,driver_version,pci.bus_id,memory.total --format=csv")
        run_cmd("bash -lci 'modinfo nvidia -F version || cat /proc/driver/nvidia/version'")
        for key in ["DISPLAY", "WAYLAND_DISPLAY", "XDG_SESSION_TYPE", "LD_PRELOAD", "LD_LIBRARY_PATH"] + sorted([k for k in os.environ if k.startswith("__GL_") or k.startswith("VK_")]):
            value = os.environ.get(key)
            print(f"{key}={value}") if value is not None else None 
        run_cmd("bash -lci 'glxinfo -B | grep \"renderer string\"'")

class CMD_config:
    def __str__(self):
        return "Configure test environment"
    
    def run(self):
        if not any(p.mountpoint == "/mnt/linuxqa" for p in psutil.disk_partitions(all=True)):
            run_cmd("sudo mkdir -p /mnt/linuxqa")
            run_cmd("sudo mount linuxqa.nvidia.com:/storage/people /mnt/linuxqa")
            print("Mounted /mnt/linuxqa")
        else:
            print("Mounted /mnt/linuxqa\t[ SKIPPED ]")

class CMD_nvmake:
    def __str__(self):
        return "Build nvidia driver"
    
    def run(self):
        config = "develop"
        arch = "aarch64"
        run_cmd([
            f"{os.environ['P4ROOT']}/tools/linux/unix-build/unix-build",
            "--unshare-namespaces", 
            "--tools",  f"{os.environ['P4ROOT']}/tools",
            "--devrel", f"{os.environ['P4ROOT']}/devrel/SDK/inc/GL",
            "nvmake",
            "NV_COLOR_OUTPUT=1",
            "NV_GUARDWORD=",
            f"NV_COMPRESS_THREADS={os.cpu_count() or 1}",
            "NV_FAST_PACKAGE_COMPRESSION=zstd",
            "NV_USE_FRAME_POINTER=1",
            "NV_UNIX_LTO_ENABLED=",
            "NV_LTCG=",
            "NV_UNIX_CHECK_DEBUG_INFO=0",
            "NV_MANGLE_SYMBOLS=",
            f"NV_TRACE_CODE={1 if config == 'release' else 0}",
            "drivers", "dist", "linux", f"{arch}", f"{config}", f"-j{os.cpu_count() or 1}"
        ], cwd=f"{os.environ['P4ROOT']}/rel/gpu_drv/r580/r580_00")
        
class CMD_nvinstall:
    def __str__(self):
        return "Install nvidia driver"
    
    def run(self):
        pass 


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