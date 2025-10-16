#!/usr/bin/env python3
import os
import sys
import stat 
import time 
import inspect
import subprocess
import psutil
import textwrap
import signal
import re
import pathlib

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


class CMD_info:
    def __str__(self):
        return "Get GPU HW and driver info"
    
    def run(self):
        subprocess.run("nvidia-smi --query-gpu=name,driver_version,pci.bus_id,memory.total --format=csv", check=True, shell=True)
        for key in ["DISPLAY", "WAYLAND_DISPLAY", "XDG_SESSION_TYPE", "LD_PRELOAD", "LD_LIBRARY_PATH"] + sorted([k for k in os.environ if k.startswith("__GL_") or k.startswith("VK_")]):
            value = os.environ.get(key)
            print(f"{key}={value}") if value is not None else None 


class CMD_config:
    def __str__(self):
        return "Configure test environment"
    
    def run(self):
        if not any(p.mountpoint == "/mnt/linuxqa" for p in psutil.disk_partitions(all=True)):
            subprocess.run("sudo mkdir -p /mnt/linuxqa", check=True, shell=True)
            subprocess.run("sudo mount linuxqa.nvidia.com:/storage/people /mnt/linuxqa", check=True, shell=True)
            print("Mounted /mnt/linuxqa")
        else: 
            print("Mounted /mnt/linuxqa \t [ SKIPPED ]")


class CMD_startx:
    def __str__(self):
        return "Start a bare X server for graphics profiling"
    
    def run(self):
        subprocess.run([
            "screen", "-S", "bareX", "-c", f"sudo X {os.environ['DISPLAY']} -ac +iglx || read -p 'Press [Enter] to exit: '"
        ], check=True)
        while not (os.path.exists("/tmp/.X11-unix/X0") \
                   and stat.S_ISSOCK(os.stat("/tmp/.X11-unix/X0").st_mode)):
            time.sleep(0.1)

        if os.path.exists(os.path.expanduser("~/sandbag-tool")):
            subprocess.run(f"{os.path.expanduser('~/sandbag-tool')} -unsandbag", check=True, shell=True)
        else:
            print("File doesn't exist: ~/sandbag-tool")
            print("Unsandbag \t [ SKIPPED ]")

        if os.uname().machine.lower() in ("aarch64", "arm64", "arm64e"):
            subprocess.run([
                "sudo", 
                "/mnt/linuxqa/wanliz/iGPU_vfmax_scripts/perfdebug",
                "--lock_loose",
                "set", "pstateId", "P0"
            ], check=True)
            subprocess.run([
                "sudo", 
                "/mnt/linuxqa/wanliz/iGPU_vfmax_scripts/perfdebug",
                "--lock_strict",
                "set", "gpcclkkHz", "2000000"
            ], check=True)
            subprocess.run([
                "sudo", 
                "/mnt/linuxqa/wanliz/iGPU_vfmax_scripts/perfdebug",
                "--lock_loose",
                "set", "xbarclkkHz", "1800000"
            ], check=True)
            subprocess.run([
                "sudo", 
                "/mnt/linuxqa/wanliz/iGPU_vfmax_scripts/perfdebug",
                "--force_regime", "ffr"
            ], check=True)


class CMD_nvmake:
    def __str__(self):
        return "Build nvidia driver"
    
    def run(self):
        if "P4ROOT" not in os.environ: 
            raise RuntimeError("P4ROOT is not defined")
        branch = input(f"{BOLD}{CYAN}[1/6] Target branch ({RESET}{DIM}[r580]{RESET}{BOLD}{CYAN}/bugfix_main): {RESET}")
        branch = "r580" if branch == "" else branch
        branch = "rel/gpu_drv/r580/r580_00" if branch == "r580" else branch 
        branch = "dev/gpu_drv/bugfix_main" if branch == "bugfix_main" else branch 
        config = input(f"{BOLD}{CYAN}[2/6] Target config ({RESET}{DIM}[develop]{RESET}{BOLD}{CYAN}/debug/release): {RESET}")
        config = "develop" if config == "" else config 
        arch   = input(f"{BOLD}{CYAN}[3/6] Target architecture ({RESET}{DIM}[amd64]{RESET}{BOLD}{CYAN}/aarch64)  : {RESET}")
        arch   = "amd64" if arch == "" else arch 
        module = input(f"{BOLD}{CYAN}[4/6] Target module ({RESET}{DIM}[drivers]{RESET}{BOLD}{CYAN}/opengl/sass): {RESET}")
        module = "drivers" if module == "" else module 
        regen  = input(f"{BOLD}{CYAN}[4a/6] Regen opengl code ({RESET}{DIM}[yes]{RESET}{BOLD}{CYAN}/no): {RESET}") if module == "opengl" else "no"
        regen  = "yes" if regen == "" else regen 
        jobs   = input(f"{BOLD}{CYAN}[5/6] Number of compiling threads ({RESET}{DIM}[{os.cpu_count()}]{RESET}{BOLD}{CYAN}/1): {RESET}")
        jobs   = str(os.cpu_count()) if jobs == "" else jobs 
        clean  = input(f"{BOLD}{CYAN}[6/6] Make a clean build ({RESET}{DIM}[no]{RESET}{BOLD}{CYAN}/yes): {RESET}")
        clean  = "no" if clean == "" else clean 

        if clean == "yes":
            subprocess.run([
                f"{os.environ['P4ROOT']}/tools/linux/unix-build/unix-build",
                "--unshare-namespaces", 
                "--tools",  f"{os.environ['P4ROOT']}/tools",
                "--devrel", f"{os.environ['P4ROOT']}/devrel/SDK/inc/GL",
                "nvmake", "sweep"
            ], cwd=f"{os.environ['P4ROOT']}/{branch}", check=True)

        subprocess.run([x for x in [
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
        ] if x is not None and x != ""], cwd=f"{os.environ['P4ROOT']}/{branch}", check=True)
        

class CMD_install:
    def __str__(self):
        return "Install nvidia driver or other packages"
    
    def run(self):
        driver = input(f"{BOLD}{CYAN}Driver path ({RESET}{DIM}[office]{RESET}{BOLD}{CYAN}/local): {RESET}")
        driver = "office" if driver == "" else driver
        if driver == "local":
            branch, config, arch, version = self.__select_nvidia_driver("local")
            driver = os.path.join(os.environ["P4ROOT"], branch, "_out", f"Linux_{arch}_{config}", f"NVIDIA-Linux-{'x86_64' if arch == 'amd64' else arch}-{version}-internal.run")
        elif driver == "office":
            branch, config, arch, version = self.__select_nvidia_driver("office")
            driver = os.path.expanduser(f"/tmp/office/_out/Linux_{arch}_{config}/NVIDIA-Linux-{'x86_64' if arch == 'amd64' else arch}-{version}-internal.run")
        else: 
            raise RuntimeError("Invalid argument")

        if not os.path.exists(driver):
            raise RuntimeError(f"File doesn't exist: {driver}")
        
        print(f"Kill all graphics apps and install $driver")
        input("Press [Enter] to continue: ")
        subprocess.run("sudo fuser -v /dev/nvidia* 2>/dev/null | awk 'NR>1 {print $3}' | sort -u | xargs -r sudo kill -9", check=True, shell=True)
        subprocess.run("while mods=$(lsmod | awk '/^nvidia/ {print $1}'); [ -n \"$mods\" ] && sudo modprobe -r $mods 2>/dev/null; do :; done", check=True, shell=True)
        subprocess.run([
            "sudo", 
            "env", 
            "IGNORE_CC_MISMATCH=1", 
            "IGNORE_MISSING_MODULE_SYMVERS=1", 
            driver, 
            "-s", 
            "--no-kernel-module-source", 
            "--skip-module-load"
        ], check=True)

    def __select_nvidia_driver(self, host):
        branch  = input(f"{BOLD}{CYAN}[1/4] Target branch ({RESET}{DIM}[r580]{RESET}{BOLD}{CYAN}/bugfix_main): {RESET}")
        branch  = "r580" if branch == "" else branch
        branch  = "rel/gpu_drv/r580/r580_00" if branch == "r580" else branch 
        branch  = "dev/gpu_drv/bugfix_main" if branch == "bugfix_main" else branch 
        config  = input(f"{BOLD}{CYAN}[2/4] Target config ({RESET}{DIM}[develop]{RESET}{BOLD}{CYAN}/debug/release): {RESET}")
        config  = "develop" if config == "" else config 
        if os.uname().machine.lower() in ("aarch64", "arm64", "arm64e"):
            arch    = input(f"{BOLD}{CYAN}[3/4] Target architecture ({RESET}{DIM}[aarch64]{RESET}{BOLD}{CYAN}/amd64): {RESET}")
            arch    = "aarch64" if arch == "" else arch 
        else:
            arch    = input(f"{BOLD}{CYAN}[3/4] Target architecture ({RESET}{DIM}[amd64]{RESET}{BOLD}{CYAN}/aarch64): {RESET}")
            arch    = "amd64" if arch == "" else arch 
        version = self.__select_nvidia_driver_version(host, branch, config, arch)
        return branch, config, arch, version 
    
    def __select_nvidia_driver_version(self, host, branch, config, arch):
        if "P4ROOT" not in os.environ: 
            raise RuntimeError("P4ROOT is not defined")
        if host == "local":
            output_dir = os.path.join(os.environ["P4ROOT"], branch, "_out", f"Linux_{arch}_{config}")
        else:
            output_dir = f"/tmp/office/_out/Linux_{arch}_{config}"
            subprocess.run(f"mkdir -p {output_dir}", check=True, shell=True)
            subprocess.run([
                "rsync", "-ah", "--progress", 
                f"wanliz@{host}:" + os.path.join(os.environ["P4ROOT"], branch, "_out", f"Linux_{arch}_{config}") + "/", 
                output_dir
            ], check=True)

        pattern = re.compile(r'^NVIDIA-Linux-(?:x86_64|aarch64)-(?P<ver>\d+\.\d+(?:\.\d+)?)-internal\.run$')
        versions = [
            match.group('ver') for path in pathlib.Path(output_dir).iterdir()
            if path.is_file() and (match := pattern.match(path.name))
        ]

        maxlen = max(v.count(".") + 1 for v in versions)
        versions.sort(
            key=lambda s: list(map(int, s.split("."))) + [0] * (maxlen - (s.count(".") + 1)),
            reverse=True,
        ) # versions[0] is the latest

        if len(versions) > 1:
            selected = input(f"{BOLD}{CYAN}[4/4] Target driver version ({RESET}{DIM}{versions[0]}{RESET}{BOLD}{CYAN}{'/'.join(versions[1:])}): {RESET}")
        elif len(versions) == 1:
            selected = versions[0]
            print(f"[4/4] Target driver version {selected} [ONLY]")
        else: 
            raise RuntimeError("No version found")

        return versions[0] if selected == "" else selected 


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
    