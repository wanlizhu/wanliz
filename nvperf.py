#!/usr/bin/env python3
import os
import sys
import inspect
import subprocess
import psutil
import platform
import signal

RESET = "\033[0m"
DIM   = "\033[90m"  
CYAN  = "\033[36m"
BOLD  = "\033[1m"
os.environ.update({
    "__GL_SYNC_TO_VBLANK": "0",
    "vblank_mode": "0",
    "__GL_DEBUG_BYPASS_ASSERT": "c",
    "PIP_BREAK_SYSTEM_PACKAGES": "1",
    "NVM_GTLAPI_USER": "wanliz",
    "NVM_GTLAPI_TOKEN": "eyJhbGciOiJIUzI1NiJ9.eyJpZCI6IjNlODVjZDU4LTM2YWUtNGZkMS1iNzZkLTZkZmZhNDg2ZjIzYSIsInNlY3JldCI6IkpuMjN0RkJuNTVMc3JFOWZIZW9tWk56a1Qvc0hpZVoxTW9LYnVTSkxXZk09In0.NzUoZbUUPQbcwFooMEhG4O0nWjYJPjBiBi78nGkhUAQ",
    "P4ROOT": "/wanliz_sw_linux",
    "P4PORT": "p4proxy-sc.nvidia.com:2006",
    "P4USER": "wanliz",
    "P4CLIENT": "wanliz_sw_linux",
    "P4IGNORE": os.path.expanduser("~/.p4ignore")
})
if not os.environ.get("DISPLAY"):    os.environ["DISPLAY"] = ":0"  
if not os.environ.get("XAUTHORITY"): os.environ["XAUTHORITY"] = os.path.expanduser("~/.Xauthority") 

signal.signal(signal.SIGINT, lambda s, f: sys.exit(0))

def run_cmd(args, cwd=f"{os.getcwd()}", newline=False):
    try:
        if isinstance(args, list):
            subprocess.run([x for x in args if x is not None and x != ""], check=True, cwd=cwd)
        elif isinstance(args, str):
            subprocess.run(["/bin/bash", "-lci", args], check=True, cwd=cwd)
        else:
            raise RuntimeError("Invalid arguments")
        if newline:
            print("")
    except (subprocess.CalledProcessError, FileNotFoundError, RuntimeError) as e:
        print(type(e).__name__, "-", e)
        exit(1)

class CMD_info:
    def __str__(self):
        return "Get GPU HW and driver info"
    
    def run(self):
        run_cmd("nvidia-smi --query-gpu=name,driver_version,pci.bus_id,memory.total --format=csv")
        run_cmd("DISPLAY=:0 glxinfo -B | grep 'renderer string' || true")
        for key in ["DISPLAY", "WAYLAND_DISPLAY", "XDG_SESSION_TYPE", "LD_PRELOAD", "LD_LIBRARY_PATH"] + sorted([k for k in os.environ if k.startswith("__GL_") or k.startswith("VK_")]):
            value = os.environ.get(key)
            print(f"{key}={value}") if value is not None else None 

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
        if "P4ROOT" not in os.environ:
            raise RuntimeError("P4ROOT is not defined")
        if not os.path.exists(f"{os.environ['P4ROOT']}/rel/gpu_drv/r580/r580_00"):
            raise RuntimeError(f"Path doesn't exist: {os.environ['P4ROOT']}/rel/gpu_drv/r580/r580_00")

        config = input(f"{BOLD}{CYAN}[1/5] Target config ({RESET}{DIM}[develop]{RESET}{BOLD}{CYAN}/debug/release): {RESET}")
        config = "develop" if config == "" else config 
        arch   = input(f"{BOLD}{CYAN}[2/5] Target architecture ({RESET}{DIM}[amd64]{RESET}{BOLD}{CYAN}/aarch64)  : {RESET}")
        arch   = "amd64" if arch == "" else arch 
        module = input(f"{BOLD}{CYAN}[3/5] Target module ({RESET}{DIM}[drivers]{RESET}{BOLD}{CYAN}/opengl/sass): {RESET}")
        module = "drivers" if module == "" else module 
        regen  = input(f"{BOLD}{CYAN}[3a/5] Regen opengl code ({RESET}{DIM}[yes]{RESET}{BOLD}{CYAN}/no): {RESET}") if module == "opengl" else "no"
        regen  = "yes" if regen == "" else regen 
        jobs   = input(f"{BOLD}{CYAN}[4/5] Number of compiling threads ({RESET}{DIM}[{os.cpu_count()}]{RESET}{BOLD}{CYAN}/1): {RESET}")
        jobs   = str(os.cpu_count()) if jobs == "" else jobs 
        clean  = input(f"{BOLD}{CYAN}[5/5] Make a clean build ({RESET}{DIM}[no]{RESET}{BOLD}{CYAN}/yes): {RESET}")
        clean  = "no" if clean == "" else clean 

        if clean == "yes":
            run_cmd([
                f"{os.environ['P4ROOT']}/tools/linux/unix-build/unix-build",
                "--unshare-namespaces", 
                "--tools",  f"{os.environ['P4ROOT']}/tools",
                "--devrel", f"{os.environ['P4ROOT']}/devrel/SDK/inc/GL",
                "nvmake", "sweep"
            ], cwd=f"{os.environ['P4ROOT']}/rel/gpu_drv/r580/r580_00")

        run_cmd([
            "time",
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
            module, 
            "dist" if module == "drivers" else "", 
            "@generate" if regen == "yes" else "",
            "linux", 
            f"{arch}", 
            f"{config}", 
            f"-j{jobs}"
        ], cwd=f"{os.environ['P4ROOT']}/rel/gpu_drv/r580/r580_00")
        
class CMD_install:
    def __str__(self):
        return "Install nvidia driver or other packages"
    
    def run(self):
        pass 

if __name__ == "__main__":
    cmds = []
    cmds_desc = []
    for name, cls in sorted(inspect.getmembers(sys.modules[__name__], inspect.isclass)):
        if cls.__module__ == __name__ and name.startswith("CMD_"):
            cmds.append(name.split("_")[1])
            cmds_desc.append(cmds[-1] + "\t:" +  str(cls()))
    
    if len(sys.argv) > 1 and sys.argv[1] in cmds:
        cmd = sys.argv[1]
    else:
        print('\n'.join(cmds_desc))
        cmd = input(f"{BOLD}{CYAN}Enter the cmd to run: {RESET}")
        if globals().get(f"CMD_{cmd}") is None:
            raise RuntimeError(f"No command class for {cmd!r}")
    cmd = globals().get(f"CMD_{cmd}")()
    cmd.run()
    