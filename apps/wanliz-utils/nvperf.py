#!/usr/bin/env python3
import os
import sys
import time 
import inspect
import subprocess
import shutil
import signal
import re
import shlex
import platform
import getpass 
import webbrowser
import ctypes
import tempfile
import importlib
import traceback
import select
import math 
import socket
import xml.etree.ElementTree as ET 
from hashlib import md5
from pathlib import Path 
from datetime import timedelta
from datetime import datetime 
from time import perf_counter
from statistics import mean, stdev
from contextlib import suppress
from itertools import zip_longest
if platform.system() == "Linux":
    import termios
    import tty 
elif platform.system() == "Windows":
    import msvcrt

def horizontal_select(prompt, options=None, index=None, separator="/", return_bool=False):
    """
    Arrow key horizontal selector that works in TTY, GNU screen, tmux,
    Windows terminal and Powershell.
    """
    from contextlib import contextmanager
    try: # Optional Linux platform bits
        import termios, tty
    except Exception:
        termios = tty = None 
    try: # Optional Windows platform bits
        import msvcrt
    except Exception:
        msvcrt = None 

    # Styling with safe fallbacks
    BOLD  = globals().get("BOLD", "")
    CYAN  = globals().get("CYAN", "")
    RESET = globals().get("RESET", "")
    DIM   = globals().get("DIM", "")
    RED   = globals().get("RED", "")

    def cast_to(val: str):
        if return_bool:  return val.lower() in ["yes", "y", "true", "t", "on", "1"]
        else: return val 
    
    global ARGPOS 
    if "ARGPOS" not in globals():
        ARGPOS = 0 
    if ARGPOS > 0 and ARGPOS < len(sys.argv):
        value = sys.argv[ARGPOS]
        ARGPOS += 1
        print(f"{BOLD}{CYAN}{prompt} : {RESET}<< {RED}{value}{RESET}")
        return cast_to(value) 
    if options is None or index is None:
        return cast_to(input(f"{BOLD}{CYAN}{prompt} : {RESET}"))
    if not (0 <= index < len(options)):
        raise RuntimeError(f"Index {index} out of range [0, {len(options)})")
    
    # Detect IO mode
    is_tty = sys.stdin.isatty() and sys.stdout.isatty()
    is_posix = (os.name == "posix" and termios and tty and is_tty)
    is_windows = (os.name == "nt" and msvcrt is not None and is_tty)

    # Fallback if no interactive terminal (e.g. IDE, redirected IO)
    if not (is_posix or is_windows):
        print("[non-interactive terminal detected]")
        return cast_to(input(f"{BOLD}{CYAN}{prompt} : {RESET}"))

    # Print prompt message
    def print_prompt(idx: int):
        opts = separator.join(
            f"{RESET}{DIM}[{o}]{RESET}{BOLD}{CYAN}" if i == idx else str(o)
            for i, o in enumerate(options)
        )
        sys.stdout.write("\r\033[2K" + f"{BOLD}{CYAN}{prompt} ({opts}): {RESET}")
        sys.stdout.flush()
    
    # POSIX key reader
    def read_posix_key(fd, timeout=0.05):
        b = os.read(fd, 1)
        if b in (b"\r", b"\n"): return "enter"
        if b == b"\x03": return "ctrl-c"
        if b != b"\x1b": return None  # Ignore regular chars
        buf = b
        while True:
            r, _, _ = select.select([fd], [], [], timeout)
            if not r: break
            buf += os.read(fd, 1)
            if buf.endswith((b"A", b"B", b"C", b"D", b"~")) or buf.endswith(b"200~") or buf.endswith(b"201~"): break
        s = buf.decode("ascii", "ignore")
        if s.endswith("D") or s == "\x1bOD": return "left"
        if s.endswith("C") or s == "\x1bOC": return "right"
        if s.endswith("A") or s == "\x1bOA": return "up"
        if s.endswith("B") or s == "\x1bOB": return "down"
        return None

    # Windows key reader 
    def read_windows_key():
        ch = msvcrt.getwch()
        if ch in ("\r", "\n"): return "enter"
        if ch == "\x03": return "ctrl-c"
        if ch in ("\x00", "\xe0"):
            tail = msvcrt.getwch()
            return {"K": "left", "M": "right", "H": "up", "P": "down"}.get(tail)
        return None
    
    @contextmanager
    def raw_io_mode(fd):
        if not is_posix:
            yield 
            return 
        old = termios.tcgetattr(fd)
        tty.setraw(fd)
        try:
            yield
        finally:
            termios.tcsetattr(fd, termios.TCSADRAIN, old)
    
    fd = sys.stdin.fileno() if is_posix else None
    selected = None 
    with raw_io_mode(fd):
        while True:
            print_prompt(index)
            key = read_windows_key() if is_windows else read_posix_key(fd)
            if key == "enter":
                sys.stdout.write("\r\n"); sys.stdout.flush()
                selected =  options[index]
                break 
            elif key == "left": index = (index - 1) % len(options)
            elif key == "right": index = (index + 1) % len(options)
            elif key == "ctrl-c":
                sys.stdout.write("\r\n"); sys.stdout.flush()
                sys.exit(0)
    value = input(": ") if selected == "<input>" else selected
    return cast_to(value)


def check_global_env():
    global RESET, DIM, RED, CYAN, BOLD 
    global ERASE_LEFT, ERASE_RIGHT, ERASE_LINE
    global STRIKE_BEGIN, STRIKE_END
    global ARGPOS, INSIDE_WSL 
    global UNAME_M, UNAME_M2, HOME, USER, IPv4

    supports_ANSI = True
    if platform.system() == "Windows": 
        if ctypes.windll.shell32.IsUserAnAdmin() == 0 and "--admin" in sys.argv:
            cmdline = subprocess.list2cmdline([os.path.abspath(sys.argv[0])] + [arg for arg in sys.argv[1:] if arg != "--admin"])
            ctypes.windll.shell32.ShellExecuteW(None, "runas", sys.executable, cmdline, None, 1)
            sys.exit(0)
        ENABLE_VT = 0x0004
        kernel32 = ctypes.windll.kernel32
        stdout = msvcrt.get_osfhandle(sys.stdout.fileno())
        mode = ctypes.c_uint()
        if not kernel32.GetConsoleMode(stdout, ctypes.byref(mode)):
            supports_ANSI = False
        elif (mode.value & ENABLE_VT) == 0:
            if not kernel32.SetConsoleMode(stdout, mode.value | ENABLE_VT):
                supports_ANSI = False

    RESET = "\x1b[0m"  if supports_ANSI else ""
    DIM   = "\x1b[90m" if supports_ANSI else ""
    RED   = "\x1b[31m" if supports_ANSI else ""
    CYAN  = "\x1b[36m" if supports_ANSI else ""
    BOLD  = "\x1b[1m"  if supports_ANSI else ""
    ERASE_RIGHT = "\x1b[0K" if supports_ANSI else "" 
    ERASE_LEFT  = "\x1b[1K" if supports_ANSI else ""
    ERASE_LINE  = "\x1b[2K" if supports_ANSI else ""
    STRIKE_BEGIN = "\x1b[9m"   if supports_ANSI else ""
    STRIKE_END   = "\x1b[29m"  if supports_ANSI else ""

    if platform.system() == "Linux":
        HOME = os.environ["HOME"] 
        HOME = HOME[:-1] if HOME.endswith("/") else HOME 
        USER = "root" if HOME == "/root" else os.environ["USER"]
    else:
        HOME = os.environ["USERPROFILE"]
        USER = os.environ["USERNAME"]

    ARGPOS = 1
    INSIDE_WSL = False
    if any(k in os.environ for k in ["WSL_DISTRO_NAME", "WSL_INTEROP", "WSLENV"]) or os.path.exists("/mnt/c/Users/"):
        INSIDE_WSL = True

    UNAME_M, UNAME_M2 = None, None 
    if platform.machine().lower() in ["x86_64", "amd64"]: UNAME_M, UNAME_M2 = "x86_64", "x64"
    elif platform.machine().lower() in ["aarch64", "arm64"]: UNAME_M, UNAME_M2 = "aarch64", "arm64"

    os.environ.update({
        "__GL_SYNC_TO_VBLANK": "0",
        "vblank_mode": "0",
        "__GL_DEBUG_BYPASS_ASSERT": "c",
        "PIP_BREAK_SYSTEM_PACKAGES": "1"
    })
    if not os.environ.get("DISPLAY"): 
        os.environ["DISPLAY"] = ":0"
        print(f"export DISPLAY={os.environ['DISPLAY']}")


def main_cmd_prompt():
    print(f"{RED}[use left/right arrow key to select from options]{RESET}")
    cmds = {}
    width = 0
    for name, cls in sorted(inspect.getmembers(sys.modules[__name__], inspect.isclass)):
        if cls.__module__ == __name__ and name.startswith("CMD_"):
            cmd_name = name.split("_")[1]
            cmds[cmd_name] = cls.__doc__
    width = max(map(len, cmds))
    for k, v in cmds.items():
        print(f"{k:>{width}} : {v}")

    cmd = horizontal_select(f"Enter the cmd to run", None, None)
    if globals().get(f"CMD_{cmd}") is None:
        raise RuntimeError(f"No command class for {cmd!r}")
    return cmd 


class Timer:
    def __init__(self, label="CPU Time Elapsed"):
        self.label = label 

    def __enter__(self):
        self.start = perf_counter()
        return self 
    
    def __exit__(self, exc_type, exc, tb):
        elapsed_sec = perf_counter() - self.start
        print(f"{self.label + ': ' if self.label else ''}{self.format(elapsed_sec)}")
        return False
    
    def format(self, sec: int) -> str:
        if sec < 1e-6: return f"{sec * 1e9 :.2f} ns"
        if sec < 1e-3: return f"{sec * 1e6:.2f} us"
        if sec < 1: return f"{sec * 1e3:.2f} ms"
        if sec < 60: return f"{sec:.2f} s"
        minute, sec = divmod(sec, 60.0)
        if minute < 60: return f"{int(minute):02d}:{sec:06.2f}"
        hour, minute = divmod(int(minute), 60)
        return f"{hour}:{minute:02d}:{sec:06.2f}"


class CMD_config:
    """Configure test environment"""

    def run(self):
        self.hosts = {
            "office": "172.16.179.143",
            "proxy": "10.176.11.106",
            "gb300-proxy": "cls-pdx-ipp6-bcm-3",
            "horizon5": "172.16.178.123",
            "horizon6": "172.16.177.182",
            "horizon7": "172.16.177.216",
            "n1x6": "10.31.40.241",
        }
        if platform.system() == "Windows":
            self.config_windows_host()
        elif platform.system() == "Linux":
            self.config_linux_host()

    def config_windows_host(self):
        pass 
        
    def config_linux_host(self):
        pass 


class CMD_info:
    pass 


class CMD_ip:
    pass 

    
class CMD_p4:
    """Perforce command tool"""

    def __init__(self):
        CMD_p4.setup_env()
        self.p4root = os.environ["P4ROOT"]

    @staticmethod
    def setup_env():
        p4client = "wanliz_sw_linux"  
        p4port = "p4proxy-sc.nvidia.com:2006"
        p4user = "wanliz"
        p4root = "/wanliz_sw_linux"  
        p4ignore = HOME + "/.p4ignore"
        subprocess.run(["bash", "-lic", rf"""
            if [[ ! -f ~/.p4ignore ]]; then 
                echo '_out' >> ~/.p4ignore
                echo '.git' >> ~/.p4ignore
                echo '.vscode' >> ~/.p4ignore
                echo '.cursorignore' >> ~/.p4ignore
                echo '.clangd' >> ~/.p4ignore
                echo '.p4config' >> ~/.p4ignore
                echo '.p4ignore' >> ~/.p4ignore
                echo 'compile-commands.json' >> ~/.p4ignore
                echo '*.code-workspace' >> ~/.p4ignore
            fi 
        """], check=True)
        os.environ.update({
            "P4CLIENT": p4client,
            "P4PORT": p4port,
            "P4USER": p4user, 
            "P4ROOT": p4root,
            "P4IGNORE": p4ignore
        })
    
    def run(self):
        subcmd = horizontal_select("Select git-emu subcmd", ["env", "status", "pull", "stash"], 0)
        if subcmd == "env":
            for x in ["P4CLIENT", "P4PORT", "P4USER", "P4ROOT", "P4IGNORE"]:
                print(f"export {x}={os.environ[x]}")
        elif subcmd == "status": self.status()
        elif subcmd == "pull": self.pull()
        elif subcmd == "stash": self.stash()

    def status(self):
        pass 

    def pull(self):
        pass 

    def stash(self):
        pass 


class CMD_sshkey:
    """Set up SSH key and copy to remote"""

    def run(self):
        host = horizontal_select("Host IP")
        user = horizontal_select("User", ["WanliZhu", "wanliz", "nvidia", "<input>"], 0)
        self.copy_to(host, user)

    def copy_to(self, host, user, passwd=None):
        pass 


class CMD_upload:
    pass 


class CMD_share:
    pass 


class CMD_mount:
    """Mount Windows or Linux shared folder"""

    def __init__(self):
        def missing_or_empty_dir(pathstr):
            path = Path(pathstr)
            if path.exists():
                return not any(path.iterdir())
            return True 
        self.mount_info = {}
        if platform.system() == "Linux":
            if missing_or_empty_dir("/mnt/linuxqa"): self.mount_info["/mnt/linuxqa"] = "linuxqa.nvidia.com:/storage/people"
            if missing_or_empty_dir("/mnt/data"): self.mount_info["/mnt/data"] = "linuxqa.nvidia.com:/storage/data"
            if missing_or_empty_dir("/mnt/builds"): self.mount_info["/mnt/builds"] = "linuxqa.nvidia.com:/storage3/builds"
            if missing_or_empty_dir("/mnt/dvsbuilds"): self.mount_info["/mnt/dvsbuilds"] = "linuxqa.nvidia.com:/storage5/dvsbuilds"
            if missing_or_empty_dir("/mnt/wanliz_sw_linux"): self.mount_info["/mnt/wanliz_sw_linux"] = "office:/wanliz_sw_linux"
    
    def run(self):
        local = horizontal_select("Select local folder", list(self.mount_info.keys()) + ["<input>"], 0)
        if local in self.mount_info:
            remote = self.mount_info[local]
        else:
            remote = horizontal_select("Input remote folder")
        self.mount(local, remote)

    def mount_all(self, ask_first):
        if ask_first and len(self.mount_info) > 0:
            confirm = horizontal_select("Mount linuxqa folders", ["yes", "no"], 0, return_bool=True)
            if not confirm: 
                return 
        for local in self.mount_info:
            self.mount(local, self.mount_info[local])

    def mount(self, local, remote):
        if platform.system() == "Linux":
            subprocess.run(["bash", "-lic", rf"""
                sudo mkdir -p {local}  
                sudo timeout 3 mount -t nfs {remote} {local} && 
                    echo "Mounted {local}" || 
                    echo "Failed to mount {local}"
            """], check=True)
        elif platform.system() == "Windows":
            if ctypes.windll.shell32.IsUserAnAdmin() == 0:
                cmdline = subprocess.list2cmdline([os.path.abspath(sys.argv[0]), "mount", remote, local])
                ctypes.windll.shell32.ShellExecuteW(None, "runas", sys.executable, cmdline, None, 1)
            else:
                remote = remote.strip().replace("/", "\\")
                remote = remote.rstrip("\\")
                unc_path = remote if remote.startswith("\\\\") else ("\\\\" + remote.lstrip("\\")) 
                drive = horizontal_select("Mount to drive", ["X", "Y", "Z"], 0)
                user = horizontal_select("Target user", ["WanliZhu", "wanliz", "nvidia", "<input>"], 0)
                subprocess.run(f'cmd /k net use {drive}: "{unc_path}" /persistent:yes {str("/user:" + user + " *") if user else ""}', check=True, shell=True)
            

class CMD_spark:
    """Configure profiling env on DGX spark"""
    # https://confluence.nvidia.com/pages/viewpage.action?spaceKey=linux&title=Digits+board+setup+for+performance

    def run(self):
        subprocess.run(["bash", "-lic", rf"""
            sudo nvidia-smi -pm 1
            sudo nvidia-persistenced
            if [[ $(uname -m) == "aarch64" ]]; then 
                sudo cp -vf /mnt/linuxqa/wlueking/n1x-bringup/environ_vars /root/nvt/environ_vars || true
                if [[ ! -f /opt/nvidia/update.sh ]]; then 
                    echo "Download spark OTA setup script"
                    curl -kL https://nv/spark-eng/eng.sh | sudo bash  || true
                    sudo /opt/nvidia/update.sh  || true
                    echo "[install new driver if OTA script failed to do so]"
                fi 
                if [[ ! -f ~/.driver || ! -f $(cat ~/.driver) ]]; then 
                    read -rp "Location of tests-Linux-$(uname -m).tar: " tests_tarball
                else
                    tests_tarball="$(dirname $(cat ~/.driver))/tests-Linux-$(uname -m).tar"
                fi 
                if [[ -f $test_tarball ]]; then 
                    sudo rm -rf /tmp/tests-Linux-$(uname -m)
                    tar -xf $tests_tarball -C /tmp
                    cp -f /tmp/tests-Linux-$(uname -m)/sandbag-tool/sandbag-tool ~
                    cp -f /tmp/tests-Linux-$(uname -m)/LockToRatedTdp/LockToRatedTdp ~
                fi 
                cd ~
                sudo chmod +x ./sandbag-tool ./LockToRatedTdp
                sudo ./sandbag-tool -unsandbag && echo "Unsandbag - [OK]" || echo "Unsandbag - [FAILED]"
                sudo ./LockToRatedTdp -lock && echo "LockToRatedTdp - [OK]" || echo "LockToRatedTdp - [FAILED]"
            fi 
            cd ~
            if [[ $(uname -m) == "aarch64" ]]; then 
                cp -vf /mnt/linuxqa/wanliz/perfdebug.aarch64 ~/perfdebug
                sudo chmod +x ./perfdebug  
                sudo ./perfdebug --lock_loose  set pstateId P0         && echo "set pstateId P0 [OK]" || echo "set pstateId P0 [OK]"
                sudo ./perfdebug --lock_strict set dramclkkHz  4266000 && echo "set dramclkkHz  4266000 - [OK]" || echo "set dramclkkHz  4266000 - [FAILED]"
                sudo ./perfdebug --lock_strict set gpcclkkHz   2000000 && echo "set gpcclkkHz   2000000 - [OK]" || echo "set gpcclkkHz   2000000 - [FAILED]"
                sudo ./perfdebug --lock_loose  set xbarclkkHz  1800000 && echo "set xbarclkkHz  1800000 - [OK]" || echo "set xbarclkkHz  1800000 - [FAILED]"
                sudo ./perfdebug --lock_loose  set sysclkkHz   1800000 && echo "set sysclkkHz   1800000 - [OK]" || echo "set sysclkkHz   1800000 - [FAILED]"
                sudo ./perfdebug --force_regime ffr  
                sudo ./perfdebug --getclocks 
            elif [[ $(uname -m) == "x86_64" ]]; then 
                cp -vf /mnt/linuxqa/wanliz/perfdebug.x86_64 ~/perfdebug
                sudo chmod +x ./perfdebug 
                sudo ./perfdebug --lock_loose  set pstateId P0         && echo "set pstateId P0 [OK]" || echo "set pstateId P0 [OK]"
                sudo ./perfdebug --lock_strict set dramclkkHz  8000000 && echo "set dramclkkHz  8000000 - [OK]" || echo "set dramclkkHz  8000000 - [FAILED]"
                sudo ./perfdebug --lock_strict set gpcclkkHz   1875000 && echo "set gpcclkkHz   1875000 - [OK]" || echo "set gpcclkkHz   1875000 - [FAILED]"
                sudo ./perfdebug --lock_loose  set xbarclkkHz  2250000 && echo "set xbarclkkHz  2250000 - [OK]" || echo "set xbarclkkHz  2250000 - [FAILED]"
                sudo ./perfdebug --lock_loose  set sysclkkHz   1695000 && echo "set sysclkkHz   1695000 - [OK]" || echo "set sysclkkHz   1695000 - [FAILED]"
                sudo ./perfdebug --force_regime ffr  
                sudo ./perfdebug --getclocks 
            fi 
        """], check=True)


class CMD_startx:
    """Start a bare X server"""
    
    def run(self):
        spark    = horizontal_select("Is this a DGX spark system", ["yes", "no"], 1, return_bool=True)
        headless = horizontal_select("Is this a headless system", ["yes", "no"], 1, return_bool=True)
        startWithDM   = horizontal_select("Do you want to run a display manager", ["yes", "no"], 1, return_bool=True)
        startWithVNC  = horizontal_select("Do you want to run a VNC server", ["yes", "no"], 1, return_bool=True)

        # Start a bare X server in GNU screen
        subprocess.run(["bash", "-lic", rf"""
            export DISPLAY=:0 
            
            # Kill running X server before starting a new one
            if [[ ! -z $(pidof Xorg) ]]; then 
                read -p "Press [Enter] to kill running X server: "    
                sudo pkill -TERM -x Xorg
                sleep 1
            fi 
            screen -ls | awk '/Detached/ && /bareX/ {{ print $1 }}' | while IFS= read -r session; do
                screen -S "$session" -X stuff $'\r'
            done
                        
            # Install package dependencies
            if [[ -z $(which xhost) ]]; then 
                sudo apt install -y x11-xserver-utils x11-utils        
            fi
            if [[ -z $(which openbox) ]]; then 
                sudo apt install -y openbox obconf     
            fi
            if [[ -z $(which x11vnc) ]]; then 
                sudo apt install -y x11vnc        
            fi
            
            if (( {1 if headless else 0} )); then 
                # Mount linuxqa folder for emulated EDID file
                if [[ ! -d /mnt/linuxqa/nvtest ]]; then 
                    sudo mkdir -p /mnt/linuxqa
                    sudo mount linuxqa.nvidia.com:/storage/people /mnt/linuxqa     
                fi 
                # Create a new xorg.conf to emulate a physical monitor 
                busID=$(nvidia-xconfig --query-gpu-info | sed -n '/PCI BusID/{{s/^[^:]*:[[:space:]]*//;p;q}}')
                sudo nvidia-xconfig -s -o /etc/X11/xorg.conf \
                    --force-generate --mode-debug --layout=Layout0 --render-accel --cool-bits=4 \
                    --mode-list=3840x2160 --depth 24 --no-ubb \
                    --x-screens-per-gpu=1 --no-separate-x-screens --busid=$busID \
                    --connected-monitor=GPU-0.DFP-0 --custom-edid=GPU-0.DFP-0:/mnt/linuxqa/nvtest/pynv_files/edids_db/ASUSPB287_DP_3840x2160x60.000_1151.bin 
                sudo screen -S bareX -dm bash -lci "__GL_SYNC_TO_VBLANK=0 X :0 -config /etc/X11/xorg.conf -logfile $HOME/X.log -logverbose 5 -ac +iglx"
            else
                sudo screen -S bareX -dm bash -lci "__GL_SYNC_TO_VBLANK=0 X :0 -logfile $HOME/X.log -logverbose 5 -ac +iglx"
            fi 

            # Wait for X server initialization
            for i in $(seq 1 10); do
                sleep 1
                if xdpyinfo >/dev/null 2>&1; then break; fi
                if [[ -z $(pidof Xorg) ]]; then echo "Failed to start X server"; exit 1; fi 
            done

            # Disable X server's access control
            xhost + || true

            # Resize to 4K display if needed 
            fbsize=$(xrandr --current 2>/dev/null | sed -n 's/^Screen .* current \([0-9]\+\) x \([0-9]\+\).*/\1x\2/p;q')
            if [[ $fbsize != "3840x2160" ]]; then 
                grep -E "Found 0 head on board" $HOME/X.log
                xrandr --fb 3840x2160
            fi 
            xrandr --current
                        
            # Start a simple display manager for windowing 
            if (( {1 if startWithDM else 0} )); then 
                screen -S openbox -dm openbox
            fi

            # Start a VNC server mirroring the new X server
            if (( {1 if startWithVNC else 0} )); then 
                if [[ -z $(sudo cat /etc/gdm3/custom.conf | grep -v '^#' | grep "WaylandEnable=false") ]]; then 
                    echo "{RED}Disable wayland before starting VNC server{RESET}"
                    exit 0
                fi 
                x11vnc -display :0  -rfbport 5900 -noshm -forever -noxdamage -repeat -shared -bg -o $HOME/x11vnc.log && echo "Start VNC server on :5900 - [OK]" || cat $HOME/x11vnc.log
            fi
        """], check=True)

        if spark: CMD_spark().run()


class CMD_nvmake:
    """Build nvidia driver"""

    def __init__(self):
        CMD_p4.setup_env()
    
    def run(self):
        if "P4ROOT" not in os.environ: 
            raise RuntimeError("P4ROOT is not defined")
        
        targets = ["drivers", "opengl", "microbench", "inspect-gpu-page-tables"]
        target = horizontal_select("Build target", [".", *targets] if os.path.exists("makefile.nvmk") else targets, 0)
        branch = horizontal_select("Target branch", ["bugfix_main", "r580"], 1)
        config = horizontal_select("Target config", ["develop", "debug", "release"], 0)
        arch   = horizontal_select("Target architecture", ["amd64", "aarch64"], 0 if UNAME_M == "x86_64" else 1)
        user_args = horizontal_select("Additional nvmake args (optional)")

        self.setup_targets(branch)
        self.run_with_config(target, config, arch, user_args)

    def setup_targets(self, branch):
        if branch == "bugfix_main": branch = f"{os.environ['P4ROOT']}/dev/gpu_drv/bugfix_main"
        if branch == "r580": branch = f"{os.environ['P4ROOT']}/rel/gpu_drv/r580/r580_00"
        self.workdirs = {
            "drivers": f"{branch}",
            "opengl":  f"{branch}/drivers/OpenGL",
            "microbench": f"{os.environ['P4ROOT']}/apps/gpu/drivers/vulkan/microbench",
            "inspect-gpu-page-tables": f"{os.environ['P4ROOT']}/pvt/aritger/apps/inspect-gpu-page-tables"
        }
        self.unixbuild_args = {
            "inspect-gpu-page-tables": f"--source {branch} --envvar NV_SOURCE={branch} --extra {os.environ['P4ROOT']}/pvt/aritger"
        }
        self.nvmake_args = {
            "drivers": "drivers dist"
        }

    def run_with_config(self, target, config, arch, user_args=None):
        nvmake_cmd = " ".join([x for x in [
            f"{os.environ['P4ROOT']}/tools/linux/unix-build/unix-build",
            "--unshare-namespaces", 
            "--tools",  f"{os.environ['P4ROOT']}/tools",
            "--devrel", f"{os.environ['P4ROOT']}/devrel/SDK/inc/GL",
            self.unixbuild_args[target] if target in self.unixbuild_args else "",
            "nvmake",
            "NV_COLOR_OUTPUT=1",
            "NV_GUARDWORD=",
            f"NV_COMPRESS_THREADS=$(nproc)",
            "NV_FAST_PACKAGE_COMPRESSION=zstd",
            "NV_USE_FRAME_POINTER=1",
            "NV_UNIX_LTO_ENABLED=",
            "NV_LTCG=",
            "NV_UNIX_CHECK_DEBUG_INFO=0",
            "NV_MANGLE_SYMBOLS=",
            f"NV_TRACE_CODE={1 if config == 'release' else 0}",
            self.nvmake_args[target] if target in self.nvmake_args else "",
            "linux", arch, config, user_args
        ] if x is not None and x != ""])
        print(nvmake_cmd)
        subprocess.run(["bash", "-lic", rf"""
            cd {self.workdirs[target] if target in self.workdirs else "."} || exit 1
            {nvmake_cmd} -j$(nproc) || {nvmake_cmd} -j1 >/dev/null 
            pwd
        """], check=True)


class CMD_inspect:
    """inspect-gpu-page-tables"""

    def run(self):
        subprocess.run(["bash", "-lic", rf"""
            if [[ ! -e /dev/nvidia-soc-iommu-inspect && $(uname -m) == "aarch64" ]]; then 
                if [[ ! -d /mnt/wanliz_sw_linux ]]; then 
                    echo "Mount /mnt/wanliz_sw_linux first"; exit 1   
                fi 
                rsync -ah --info=progress2 /mnt/wanliz_sw_linux/pvt/aritger/apps/inspect-gpu-page-tables/nvidia-soc-iommu-inspect /tmp 
                cd /tmp/nvidia-soc-iommu-inspect || exit 1
                make || exit 1
                sudo insmod ./nvidia-soc-iommu-inspect.ko 
                sudo ./create-dev-node.sh
            fi 
            if [[ ! -f ~/inspect-gpu-page-tables ]]; then 
                cp -vf /mnt/linuxqa/wanliz/inspect-gpu-page-tables.$(uname -m) ~/inspect-gpu-page-tables
            fi 
            cd ~ && sudo ./inspect-gpu-page-tables 
        """], check=True)
        

class CMD_rmmod:
    """Remove loaded kernel modules of nvidia driver"""
    
    def run(self, retry=True):
        try:
            subprocess.run(["bash", "-lic", r"""
                sudo rm -f /tmp/nvidia_pids
                sudo systemctl stop gdm sddm lightdm nvidia-persistenced nvidia-dcgm 2>/dev/null || true
                sudo lsof  -t /dev/nvidia* /dev/dri/{card*,renderD*} 2>/dev/null >>/tmp/nvidia_pids
                sudo grep -El 'lib(nvidia|cuda|GLX_nvidia|EGL_nvidia|nvoptix|nvrm|nvcuvid)' /proc/*/maps 2>/dev/null | sed -E 's@/proc/([0-9]+)/maps@\1@' >>/tmp/nvidia_pids 
                awk '{for (i=1; i<=NF; i++) print $i}' /tmp/nvidia_pids | sort -u | while IFS= read -r pid; do 
                    [[ $pid =~ ^[0-9]+$ ]] || continue
                    [[ $pid -eq 1 || $pid -eq $$ ]] && continue
                    sudo kill -9 $pid  
                done 
                echo "[DGX station: don't forget to restart nvidia-dcgm]"
            """], check=True) 
        except Exception:
            if retry: self.run(retry=False)
            else: raise
    
class CMD_install:
    """Install nvidia driver or other packages"""
    
    def run(self):
        CMD_p4.setup_env()
        p4root = os.environ["P4ROOT"]

        location = horizontal_select("Select driver location", ["office build", "local build", "<input>"], 0)
        if location == "local build":
            branch, config, arch, version = self.select_nvidia_driver(p4root)
            driver = os.path.join(p4root, branch, "_out", f"Linux_{arch}_{config}", f"NVIDIA-Linux-{'x86_64' if arch == 'amd64' else arch}-{version}-internal.run")
        elif location == "office build":
            branch, config, arch, version = self.select_nvidia_driver(p4root)  
            driver = f"/mnt{p4root}/_out/Linux_{arch}_{config}/NVIDIA-Linux-{'x86_64' if arch == 'amd64' else arch}-{version}-internal.run"
        elif location == "redo":
            driver = Path(f"{HOME}/.driver").read_text(encoding="utf-8").rstrip("\n")
        else:
            driver = location 
        if not os.path.exists(driver):
            raise RuntimeError(f"File not found: {driver}")
        print(driver)
        
        interactive = horizontal_select("Do you want to install in interactive mode", ["yes", "no"], 0, return_bool=True)
        CMD_rmmod().run()
        subprocess.run(["bash", "-lic", rf"""
            chmod +x {driver}
            sudo env IGNORE_CC_MISMATCH=1 IGNORE_MISSING_MODULE_SYMVERS=1 {driver} {'' if interactive else '-s --no-kernel-module-source --skip-module-load'} && sleep 3 &&  nvidia-smi
            echo "{driver}" > ~/.driver
            echo "Updated ~/.driver"
        """], check=True)

    def select_nvidia_driver(self, p4root):
        branch  = horizontal_select("Target branch", ["r580", "bugfix_main"], 0)
        branch  = "rel/gpu_drv/r580/r580_00" if branch == "r580" else branch 
        branch  = "dev/gpu_drv/bugfix_main" if branch == "bugfix_main" else branch 
        config  = horizontal_select("Target config", ["develop", "debug", "release"], 0)
        arch    = horizontal_select("Target architecture", ["amd64", "aarch64"], 1 if os.uname().machine.lower() in ("aarch64", "arm64", "arm64e") else 0)
        version = self.select_nvidia_driver_version(p4root, branch, config, arch)
        return branch, config, arch, version 
    
    def select_nvidia_driver_version(self, p4root, branch, config, arch):
        if "P4ROOT" not in os.environ: 
            raise RuntimeError("P4ROOT is not defined")
        
        output_dir = os.path.join(p4root, branch, "_out", f"Linux_{arch}_{config}")
        pattern = re.compile(r'^NVIDIA-Linux-(?:x86_64|aarch64)-(?P<ver>\d+\.\d+(?:\.\d+)?)-internal\.run$')
        versions = [
            match.group('ver') for path in Path(output_dir).iterdir()
            if path.is_file() and (match := pattern.match(path.name))
        ]
        maxlen = max(v.count(".") + 1 for v in versions)
        versions.sort(
            key=lambda s: list(map(int, s.split("."))) + [0] * (maxlen - (s.count(".") + 1)),
            reverse=True,
        ) # versions[0] is the latest

        if len(versions) > 1: return horizontal_select("Target driver version", versions, 0)
        elif len(versions) == 1: return versions[0]
        else: raise RuntimeError("No version found")
    

class CMD_download:
    """Download packages or resources"""

    def __init__(self):
        if not os.path.exists("/mnt/linuxqa/wanliz"):
            raise RuntimeError("Mount /mnt/linuxqa first")

    def run(self):
        src = horizontal_select("Download", [
            "Perf Inspector",
            "Nsight graphics",
            "Nsight systems", 
            "viewperf",
            "GravityMark",
            "3dMark - steelNomad",
            "Microbench"
        ], 0)
        if src == "Perf Inspector": self.download_pi()
        elif src == "Nsight graphics": self.download_nsight_graphics()
        elif src == "Nsight systems": self.download_nsight_systems() 
        elif src == "viewperf": self.download_viewperf()
        elif src == "GravityMark": self.download_gravitymark()
        elif src == "3dMark - steelNomad": self.download_3dMark("steelNomad")
        elif src == "Microbench": self.download_microbench()

    def download_pi(self):
        pass # TODO 

    def download_nsight_graphics(self):
        webbrowser.open("https://ngfx/builds-nightly/Grfx")

    def download_nsight_systems(self): 
        webbrowser.open("https://urm.nvidia.com/artifactory/swdt-nsys-generic/ctk")

    def download_viewperf(self):
        if os.path.exists(f"/mnt/linuxqa/wanliz/viewperf2020v3.{UNAME_M}"):
            print(f"Downloading {HOME}/viewperf2020v3")
            subprocess.run(["bash", "-lic", f"rsync -ah --info=progress2 /mnt/linuxqa/wanliz/viewperf2020v3.{UNAME_M}/ $HOME/viewperf2020v3"], check=True)
        else: raise RuntimeError(f"Folder not found: /mnt/linuxqa/wanliz/viewperf2020v3.{UNAME_M}")

    def download_gravitymark(self):
        if os.path.exists(f"/mnt/linuxqa/wanliz/gravity_mark.{UNAME_M}"):
            print(f"Downloading {HOME}/gravity_mark")
            subprocess.run(["bash", "-lic", f"rsync -ah --info=progress2 /mnt/linuxqa/wanliz/gravity_mark.{UNAME_M}/ $HOME/gravity_mark"], check=True)
        else: raise RuntimeError(f"Folder not found: /mnt/linuxqa/wanliz/gravity_mark.{UNAME_M}") 

    def download_3dMark(self, name):
        if os.path.exists(f"/mnt/linuxqa/wanliz/3dMark_{name}.{UNAME_M}"):
            print(f"Downloading {HOME}/3dMark_{name}")
            subprocess.run(["bash", "-lic", f"rsync -ah --info=progress2 /mnt/linuxqa/wanliz/3dMark_{name}.{UNAME_M}/ $HOME/3dMark_{name}"], check=True)
        else: raise RuntimeError(f"Folder not found: /mnt/linuxqa/wanliz/3dMark_{name}.{UNAME_M}")  

    def download_microbench(self):
        if os.path.exists(f"/mnt/linuxqa/wanliz/nvperf_vulkan.{UNAME_M}"):
            print(f"Downloading {HOME}/nvperf_vulkan")
            subprocess.run(["bash", "-lic", f"rsync -ah --info=progress2 /mnt/linuxqa/wanliz/nvperf_vulkan.{UNAME_M} {HOME}/nvperf_vulkan"], check=True)
        else: raise RuntimeError(f"File not found: /mnt/linuxqa/wanliz/nvperf_vulkan.{UNAME_M}")


class CMD_cpu:
    """Configure CPU on host device"""
    
    def run(self):
        cmd = horizontal_select("Action", ["max freq"], 0)
        if cmd == "max freq":
            subprocess.run(["bash", "-lic", rf"""
                for core in `seq 0 $(( $(nproc) - 1 ))`; do 
                    cpufreq="/sys/devices/system/cpu/cpu$core/cpufreq"
                    sudo rm -rf /tmp/$cpufreq
                    max=$(cat $cpufreq/cpuinfo_max_freq)
                    echo performance  | sudo tee $cpufreq/scaling_governor >/dev/null 
                    echo $max | sudo tee $cpufreq/scaling_max_freq >/dev/null 
                    echo $max | sudo tee $cpufreq/scaling_min_freq >/dev/null 
                done 
            """], check=True)


class CPU_freq_limiter:
    def scale_max_freq(self, scale):
        self.reset()
        subprocess.run(["bash", "-lic", rf"""
            for core in `seq 0 $(( $(nproc) - 1 ))`; do 
                cpufreq="/sys/devices/system/cpu/cpu$core/cpufreq"
                sudo rm -rf /tmp/$cpufreq
                sudo cp -rf $cpufreq /tmp/ 
                max=$(cat $cpufreq/cpuinfo_max_freq)
                scaled_freq=$(LC_ALL=C awk -v r="{scale}" -v m="$max" 'BEGIN{{printf "%.0f", r*m}}')
                echo powersave    | sudo tee $cpufreq/scaling_governor >/dev/null 
                echo $scaled_freq | sudo tee $cpufreq/scaling_max_freq >/dev/null 
                echo $scaled_freq | sudo tee $cpufreq/scaling_min_freq >/dev/null 
            done 
        """], check=True)
        
    def reset(self):
        subprocess.run(["bash", "-lic", rf"""
            for core in `seq 0 $(( $(nproc) - 1 ))`; do 
                cpufreq="/sys/devices/system/cpu/cpu$core/cpufreq"
                if [[ -d /tmp/$cpufreq ]]; then 
                    sudo cp -rf /tmp/$cpufreq $cpufreq/../
                fi 
            done 
        """], check=True)


class GPU_freq_limiter:
    def scale_max_freq(self, scale):
        pass 

    def reset(self):
        pass 


class Test_info:
    def input(self):
        self.exe=horizontal_select("Target exe path", [f"viewperf", f"3dMark_steelNomad", f"vkcube", "<input>"], 0)
        if self.exe == "viewperf":
            self.exe = f"{HOME}/viewperf2020v3/viewperf/bin/viewperf"
            viewset = horizontal_select("Select viewset", ["catia", "creo", "energy", "maya", "medical", "snx", "sw"], 3)
            self.arg = f"viewsets/{viewset}/config/{viewset}.xml -resolution 3840x2160"
            self.workdir = "{HOME}/viewperf2020v3"
            self.env = None 
            self.api = "ogl"
        elif self.exe == "3dMark_steelNomad":
            self.exe = f"{HOME}/3dMark_steelNomad/engine/build/bin/dev_player"
            self.arg = f"--asset_root=../assets_desktop --config=configs/gt1.json"
            self.workdir = f"{HOME}/3dMark_steelNomad/engine"
            self.env = None 
            self.api = "vk"
        elif self.exe == "vkcube":
            self.exe = "/usr/bin/vkcube"
            self.arg = ""
            self.workdir = ""
            self.env = None 
            self.api = "vk"
        else:
            self.arg = horizontal_select("Target arguments (optional)")
            self.workdir = horizontal_select("Target workdir (optional)")
            self.env = None 
            self.api = horizontal_select("Target graphics API", ["ogl", "vk"], 0)
        if not os.path.exists(self.exe):
            raise RuntimeError(f"File not found: {self.exe}")
        return self 

class CMD_pi:
    """Perf Inspector"""

    def __init__(self):
        self.pi_root = HOME + "/SinglePassCapture" 
        if not os.path.exists(self.pi_root):
            CMD_download().download_pi()
    
    def run(self):
        subcmd = horizontal_select("Select subcmd", ["exe mode", "server mode", "upload report", "fix me"], 0)
        if subcmd == "exe mode":
            test = Test_info().input()
            startframe = horizontal_select("Start capturing at frame index", ["100", "<input>"], 0)
            frames = horizontal_select("Number of frames to capture", ["3", "<input>"], 0)
            debug = horizontal_select("Do you want to enable pic-x debugging", ["yes", "no"], 1, return_bool=True)
            self.launch_and_capture(exe=test.exe, arg=test.arg, workdir=test.workdir, api=test.api, startframe=startframe, frames=frames, debug=debug)
        elif subcmd == "server mode":
            api = horizontal_select("Capture graphics API", ["ogl", "vk"], 0)
            frames = horizontal_select("Number of frames to capture", ["3", "<input>"], 0)
            debug = horizontal_select("Do you want to enable pic-x debugging", ["yes", "no"], 1, return_bool=True)
            self.run_in_server_mode(api=api, frames=frames, debug=debug)
        elif subcmd == "upload report":
            reports = sorted([p.name for p in Path(self.pi_root + "/PerfInspector/output").iterdir() 
                              if p.is_dir() and p.name != "perf_inspector_v2"])
            name = horizontal_select("Select a report to upload", reports, 0)
            self.upload_report(name=name)
        elif subcmd == "fix me":
            self.fix_me()

    def launch_and_capture(self, exe, arg, workdir, api, startframe=100, frames=3, debug=False):
        subprocess.run([x for x in [
            "sudo", "env", "DISPLAY=:0",
            self.pi_root + "/pic-x",
            "--check_clocks=0",
            "--clean=0" if debug else "",
            f"--api={api}",
            f"--startframe={startframe}",
            f"--frames={frames}",
            f"--exe={exe}",
            f"--arg={arg}",
            f"--workdir={workdir}"
        ] if len(x) > 0], check=True)

    def run_in_server_mode(self, api, frames, debug=False):
        subprocess.run(["bash", "-lic", rf"""
            export LD_LIBRARY_PATH={self.pi_root}
            python3 {self.pi_root}/Scripts/VkLayerSetup/SetImplicitLayer.py --install
            sudo {self.pi_root}/pic-x --api={api} --check_clocks=0 {"--clean=0" if debug else ""} --frames={frames} --trigger=1
            python3 {self.pi_root}/Scripts/VkLayerSetup/SetImplicitLayer.py --uninstall
        """], check=True)

    def upload_report(self, name):
        if os.path.exists(self.pi_root+f"/PerfInspector/output/{name}"):
            subprocess.run(["bash", "-lic", "NVM_GTLAPI_USER=wanliz NVM_GTLAPI_TOKEN='eyJhbGciOiJIUzI1NiJ9.eyJpZCI6IjNlODVjZDU4LTM2YWUtNGZkMS1iNzZkLTZkZmZhNDg2ZjIzYSIsInNlY3JldCI6IkpuMjN0RkJuNTVMc3JFOWZIZW9tWk56a1Qvc0hpZVoxTW9LYnVTSkxXZk09In0.NzUoZbUUPQbcwFooMEhG4O0nWjYJPjBiBi78nGkhUAQ' ./upload_report.sh"], 
                            cwd=self.pi_root+f"/PerfInspector/output/{name}", 
                            check=True)
    
    def fix_me(self):
        subprocess.run(["bash", "-lic", rf"""
            sudo apt autoremove 
            sudo apt install -y python3-venv python3-pip 
            sudo mv -f -t /tmp {self.pi_root}/PerfInspector/Python-venv  
            python3 -m venv {self.pi_root}/PerfInspector/Python-venv
            {self.pi_root}/PerfInspector/Python-venv/bin/python -m pip install -r {self.pi_root}/Scripts/requirements.txt || true
            {self.pi_root}/PerfInspector/Python-venv/bin/python -m pip install -r {self.pi_root}/PerfInspector/processing/requirements.txt || true 
            {self.pi_root}/PerfInspector/Python-venv/bin/python -m pip install -r {self.pi_root}/PerfInspector/processing/requirements_0.txt || true 
            {self.pi_root}/PerfInspector/Python-venv/bin/python -m pip install -r {self.pi_root}/PerfInspector/processing/requirements_perfsim.txt || true 
            {self.pi_root}/PerfInspector/Python-venv/bin/python -m pip install -r {self.pi_root}/PerfInspector/processing/requirements_with_extra_index.txt || true 
            {self.pi_root}/PerfInspector/Python-venv/bin/python -m pip install --index-url https://sc-hw-artf.nvidia.com/artifactory/api/pypi/hwinf-pi-pypi/simple --extra-index-url https://pypi.perflab.nvidia.com/ --extra-index-url https://urm.nvidia.com/artifactory/api/pypi/nv-shared-pypi/simple marisa-trie python-rapidjson memory-profiler py7zr ruyi_formula_calculator idea2txv==0.21.17 perfins==0.5.47 gtl-api==2.25.5 hair-cli pi-uploader wget apm xgboost ruyi-formula-calculator perfins PIFlod lttb idea2txv Pillow psutil==5.9.3 pyyaml joblib xlsxwriter seaborn scikit-learn numexpr openpyxl keyring==23.4.0 requests==2.27.1 requests-toolbelt==0.9.1 tqdm==4.62.3 aem ipdb==0.13.0 dask[complete] prettytable || true
            if ! grep -Rhs --include='*.conf' -v '^[[:space:]]*#' /etc/modprobe.d /etc/modprob.d | grep -q 'NVreg_RestrictProfilingToAdminUsers=0' || ! grep -Rhs --include='*.conf' -v '^[[:space:]]*#' /etc/modprobe.d /etc/modprob.d | grep -Eq '(^|[;[:space:]])RmProfilerFeature=0x1([;[:space:]]|"|$)'; then
                echo "Missing one or both settings: NVreg_RestrictProfilingToAdminUsers=0 and RmProfilerFeature=0x1"
            fi
        """], check=True)
    
        
class CMD_ngfx:
    """Nsight graphics"""

    def __init__(self):
        self.get_ngfx_path()
        if not os.path.exists(self.ngfx):
            CMD_download().download_nsight_graphics()
            self.get_ngfx_path()
        self.get_arch()
        self.get_metricset()
        self.help_all = subprocess.run(["bash", "-lic", f"{self.ngfx} --help-all"], check=False, capture_output=True, text=True).stdout
        
    def run(self):
        # for N1x: --architecture="T254 GB20B" --metric-set-name="Top-Level Triage"
        test = Test_info().input()
        startframe = horizontal_select("Start capturing at frame index", ["100", "<input>"], 0)
        frames = horizontal_select("Number of frames to capture", ["3", "<input>"], 0)
        time_all_actions = horizontal_select("Do you want to time all API calls separately", ["yes", "no"], 1, return_bool=True)
        self.capture(exe=test.exe, args=test.arg, workdir=test.workdir, env=None, startframe=startframe, frames=frames, time_all_actions=time_all_actions)

    def fix_me(self):
        subprocess.run(["bash", "-lic", rf"""
            echo "Checking package dependencies of Nsight graphics..."
            for pkg in libxcb-dri2-0 libxcb-shape0 libxcb-xinerama0 libxcb-xfixes0 libxcb-render0 libxcb-shm0 libxcb1 libx11-xcb1 libxrender1 \
                libxkbcommon0 libxkbcommon-x11-0 libxext6 libxi6 libglib2.0-0 libglib2.0-0t64 libegl1 libopengl0 \
                libxcb-util1 libxcb-cursor0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-randr0 libxcb-render-util0 libxcb-xinput0; do 
                dpkg -s $pkg &>/dev/null || sudo apt install -y $pkg &>/dev/null
            done 
        """], check=True)

    def capture(self, exe, arg, workdir, env=None, startframe=100, frames=3, time_all_actions=False): 
        subprocess.run(["bash", "-lic", ' '.join([line for line in [
            'sudo env DISPLAY=:0', self.ngfx,
            '--output-dir=$HOME',
            '--platform="Linux ($(uname -m))"',
            f'--exe="{exe}"',
            f'--args="{arg}"' if arg else "",
            f'--dir="{workdir}"' if workdir else "",
            f'--env="{"; ".join(env)}"' if env else "",
            '--activity="GPU Trace Profiler"',
            f'--start-after-frames={startframe}',
            f'--limit-to-frames={frames}',
            '--auto-export',
            f'--architecture="{self.arch}"', 
            f'--metric-set-name="{self.metricset}"',
            '--multi-pass-metrics',
            '--real-time-shader-profiler',
            '--time-every-action' if time_all_actions else ""
        ] if len(line) > 0])], check=True) 

    def get_ngfx_path(self):
        if platform.machine() == 'aarch64':
            self.ngfx = f'{HOME}/nvidia-nomad-internal-EmbeddedLinux.l4t/host/linux-v4l_l4t-nomad-t210-a64/ngfx'
        elif os.path.isdir(f'{HOME}/nvidia-nomad-internal-Linux.linux'):
            self.ngfx = f'{HOME}/nvidia-nomad-internal-Linux.linux/host/linux-desktop-nomad-x64/ngfx'
        elif os.path.isdir(f'{HOME}/nvidia-nomad-internal-EmbeddedLinux.linux'):
            self.ngfx = f'{HOME}/nvidia-nomad-internal-EmbeddedLinux.linux/host/linux-desktop-nomad-x64/ngfx'
        else:
            self.ngfx = shutil.which('ngfx')

    def get_arch(self):
        if not os.path.exists(self.ngfx):
            return 
        arch_list =  [l.strip() for l in re.search(r'Available architectures:\n((?:\s{2,}.+\n)+)', self.help_all).group(1).splitlines()]
        arch_list = arch_list[:next((i for i, x in enumerate(arch_list) if x == '' or x.startswith("-")), len(arch_list))] 
        self.arch = horizontal_select("Select architecture", arch_list, 0)

    def get_metricset(self):
        if not os.path.exists(self.ngfx):
            return 
        indent_base = -1
        indent_arch = -1
        arch_name = None 
        metricset_map = {}
        for line in [line.rstrip() for line in self.help_all.splitlines()]:
            if indent_base < 0:
                if "--metric-set-id" in line:
                    indent_base = line.find("Index")
                continue 
            if len(line) == 0 or line.startswith("-"):
                break 

            indent_line = len(line) - len(line.lstrip())
            if indent_line <= indent_base:
                continue 
            if indent_arch < 0 or indent_line == indent_arch:
                indent_arch = indent_line
                arch_name = line.strip()
                metricset_map[arch_name] = []
                continue 
            if indent_line > indent_arch and arch_name:
                metricset_map[arch_name].append(line.split('-', 1)[1].strip())
                continue 
        if len(metricset_map) == 0 or not metricset_map.get(self.arch):
            raise RuntimeError(f"Failed to find metric sets for {self.arch}")
        if len(metricset_map[self.arch]) == 1:
            self.metricset = metricset_map[self.arch][0]
            print(f"Metric set: {self.metricset}")
        else:
            self.metricset = horizontal_select("Select metric set", metricset_map[self.arch], 0)
            

class CMD_nsys:
    """Nsight systems"""
    
    def run(self):
        test = Test_info().input()
        startframe = horizontal_select("Start capturing at frame index", ["100", "<input>"], 0)
        self.capture(exe=test.exe, arg=test.arg, workdir=test.workdir, startframe=startframe)

    def capture(self, exe, arg, workdir, startframe=100):
        subprocess.run(["bash", "-lic", rf"""
            cd {workdir}
            echo "Nsight system exe: $(which nsys)"
            sudo "$(which nsys)" profile \
                --run-as={getpass.getuser()} \
                --sample='system-wide' \
                --event-sample='system-wide' \
                --stats=true \
                --trace='cuda,nvtx,osrt,opengl' \
                --opengl-gpu-workload=true \
                --start-frame-index={startframe} \
                --duration-frames=60  \
                --gpu-metrics-devices=all  \
                --gpuctxsw=true \
                --output="viewperf_medical__%h__$(date '+%Y_%m%d_%H%M')" \
                --force-overwrite=true \
                {exe} {arg}
        """], cwd=workdir, check=True) 


class Table_view:
    def __init__(self, columns: list, header: list):
        self.columns = columns 
        self.header = header 
        if self.columns and not self.header:
            self.header = [f"Column {c}" for c in range(len(self.columns))]

    def init_with_dict(self, data):
        self.header = list(data.keys())
        self.columns = [data[name] for name in self.header]
    
    def print(self, logfile_prefix=None):
        if not (self.columns and self.header):
            print("[columns and header are none]")
            return 
        try:
            # Append avg and cv to each column 
            for i, column in enumerate(self.columns):
                avg = mean(column)
                avg_is_zero = math.isclose(avg, 0.0, rel_tol=0.0, abs_tol=1e-12)
                cv = (stdev(column) / avg) if (len(column) >= 2 and not avg_is_zero) else 0
                column += [avg, cv]
                column.insert(0, self.header[i])

            # Add label column 
            self.columns.insert(0, [])
            self.columns[0].append(" ")
            samples_num = len(self.columns[1]) - 1 - 2
            self.columns[0] += [f"Index {i}" for i in range(1, samples_num + 1)]
            self.columns[0] += ["Average", "CV"]

            # Transpose to rows for rendering 
            rows = [list(col) for col in zip_longest(*self.columns, fillvalue="")]
            def format_cell(r, c, val):
                if r == 0 or c == 0:   return f"{val}"
                if rows[r][0] == "CV": return f"{val:.3%}"
                else: return f"{val:.3f}"
            columns_width = [
                max(4, max(len(format_cell(r, c, rows[r][c])) for r in range(len(rows))))
                for c in range(len(rows[0]))
            ]
            total_width = sum(columns_width) + len(columns_width) * 2 - 2 + 3
            
            # Build lines 
            lines = []
            for r, row in enumerate(rows):
                left = f"{str(row[0]):<{columns_width[0]}}  |  "
                right = "  ".join(format_cell(r, c, row[c]).rjust(columns_width[c]) for c in range(1, len(row))) 
                lines.append(left + right)
            
            # Separators 
            lines.insert(1, "-" * total_width)
            lines.insert(len(lines) - 2, "-" * total_width)
          
            if logfile_prefix is not None:
                timestamp = datetime.now().strftime('%Y_%m%d_%H%M')
                with open(HOME + f"/{logfile_prefix}{timestamp}.txt", "w", encoding="utf-8") as file:
                    file.write("\n".join(lines))
            print("\n".join(lines))
        except Exception:
            traceback.print_exc()
            lines = [f"{name:>9}:  " + "  ".join([f"{x:>7.2f}" for x in self.columns[index]]) for index, name in enumerate(self.header)]
            print("\n" + "\n".join(lines))


class CMD_gdb:
    """Run program in GDB"""

    def run(self):
        test = Test_info().input()
        self.run_in_gdb(exe=test.exe, arg=test.arg, workdir=test.workdir, env=test.env) 

    def run_in_gdb(self, exe, arg, workdir, env=None):
        env_lines = "\n".join([
            f"gdbenv+=( -ex 'set env {k} {v}' )" 
            for k, v in (
                (kv.split('=', 1)[0], kv.split('=', 1)[1])
                for kv in (env or []) if '=' in kv 
            ) 
        ])
        subprocess.run(["bash", "-lic", rf"""
            if ! command -v cgdb >/dev/null 2>&1; then
                sudo apt install -y cgdb
            fi 
            
            gdbenv=()
            while IFS='=' read -r k v; do 
                gdbenv+=( -ex "set env $k $v" )
            done < <(env | grep -E '^(__GL_|LD_)')
            {env_lines}

            cd {workdir}
            cgdb -- \
                -ex "set trace-commands on" \
                -ex "set pagination off" \
                -ex "set confirm off" \
                -ex "set debuginfod enabled on" \
                -ex "set breakpoint pending on" \
                "${{gdbenv[@]}}" \
                -ex "file {exe}" \
                -ex "set args {arg}" \
                -ex "set trace-commands off"
        """], check=True)


class CMD_viewperf:
    """Profiling viewperf 2020 v3"""
    
    def run(self):
        self.viewperf_root = HOME + "/viewperf2020v3"
        if not os.path.exists(self.viewperf_root):
            CMD_download().download_viewperf()

        timestamp = perf_counter()
        subtest_nums = { "catia": 8, "creo": 13, "energy": 6, "maya": 10, "medical": 10, "snx": 10, "sw": 10 }
        self.viewset = horizontal_select("Target viewset", ["all", "catia", "creo", "energy", "maya", "medical", "snx", "sw"], 4)
        if self.viewset == "all":
            env = "stats"
        else:
            self.subtest = horizontal_select("Target subtest", ["all"] + [str(i) for i in range(1, subtest_nums[self.viewset] + 1)], 0)
            self.subtest = "" if self.subtest == "all" else self.subtest
            env = horizontal_select("Launch in profiling/debug env", ["stats", "picx", "ngfx", "nsys", "gdb", "limiter"], 0)
            self.exe = self.viewperf_root + '/viewperf/bin/viewperf'
            self.arg = f"viewsets/{self.viewset}/config/{self.viewset}.xml {self.subtest} -resolution 3840x2160" 
            self.dir = self.viewperf_root
    
        if env == "stats":
            self.run_in_stats()
        elif env == "picx":
            startframe = horizontal_select("Start capturing at frame index", ["100", "<input>"], 0)
            frames = horizontal_select("Number of frames to capture", ["3", "<input>"], 0)
            debug = horizontal_select("Do you want to enable pic-x debugging", ["yes", "no"], 1, return_bool=True)
            CMD_pi().launch_and_capture(exe=self.exe, arg=self.arg, workdir=self.dir, api="ogl", startframe=startframe, frames=frames, debug=debug)
        elif env == "ngfx":
            startframe = horizontal_select("Start capturing at frame index", ["100", "<input>"], 0)
            frames = horizontal_select("Number of frames to capture", ["3", "<input>"], 0)
            time_all_actions = horizontal_select("Do you want to time all API calls separately", ["yes", "no"], 1, return_bool=True)
            CMD_ngfx().capture(exe=self.exe, arg=self.arg, workdir=self.dir, startframe=startframe, frames=frames, time_all_actions=time_all_actions)
        elif env == "nsys":
            CMD_nsys.capture(exe=self.exe, arg=self.arg, workdir=self.dir)
        elif env == "gdb":
            CMD_gdb().run_in_gdb(exe=self.exe, arg=self.arg, workdir=self.dir)
        elif env == "limiter":
            self.run_in_limiter()
        
        print(f"\nTime elapsed: {str(timedelta(seconds=perf_counter()-timestamp)).split('.')[0]}")
    
    def get_result_fps(self, viewset, subtest):
        try:
            pattern = f"results/{'solidworks' if viewset == 'sw' else viewset}-*/results.xml"
            matches = list(Path(self.viewperf_root).glob(pattern))
            if not matches:
                raise RuntimeError(f"Failed to find results of {viewset}")

            results_xml = max(matches, key=lambda p: p.stat().st_mtime) 
            root = ET.parse(results_xml).getroot()

            if subtest:
                return root.find(f".//Test[@Index='{subtest}']").get("FPS")
            else:
                return root.find("Composite").get("Score")
        except Exception:
            return 0
        
    def run_in_stats(self):
        subprocess.run(["bash", "-lic", "DISPLAY=:0 glxinfo -B | grep 'OpenGL renderer'"], check=True)
        viewsets = ["catia", "creo", "energy", "maya", "medical", "snx", "sw"] if self.viewset == "all" else [self.viewset]
        subtest = None if self.viewset == "all" else self.subtest
        rounds = int(horizontal_select("Number of rounds", ["1", "3", "10", "30"], 0))
        raw_data = []
        for viewset in viewsets:
            samples = []
            for i in range(1, rounds + 1):
                output = subprocess.run([x for x in [
                        f"{self.viewperf_root}/viewperf/bin/viewperf", 
                        f"viewsets/{viewset}/config/{viewset}.xml", 
                        f"{subtest if subtest else ''}", 
                        "-resolution", "3840x2160"
                    ] if len(x) > 0],
                    cwd=self.viewperf_root, 
                    check=False, 
                    text=True,
                    capture_output=True
                )
                fps = float(self.get_result_fps(viewset, subtest)) if output.returncode == 0 else 0 
                samples.append(fps)
                print(f"{viewset}{subtest if subtest else ''} @ run {i:02d}: {fps: 3.2f} FPS")
            raw_data.append(samples) 
        print("")
        Table_view(columns=raw_data, header=viewsets).print(logfile_prefix="viewperf_stats_")

    def run_in_limiter(self):
        choice = horizontal_select("Emulate perf limiter of", ["CPU", "GPU"], 1)
        lowest = horizontal_select("Emulation lower bound", ["50%", "33%", "10%"], 0)
        lowest = 5 if lowest == "50%" else (3 if lowest == "33%" else 1)
        limiter = None 
        try:
            limiter = CPU_freq_limiter() if choice == "CPU" else GPU_freq_limiter()
            for scale in [x / 10 for x in range(lowest, 11, 1)]:
                limiter.scale_max_freq(scale)
                subprocess.run(["bash", "-lic", f"{self.exe} {self.arg}"], cwd=self.dir, check=True, capture_output=True)
                print(f"{self.viewset}{self.subtest}: {self.get_result_fps(self.viewset, self.subtest)} @ {scale:.1f}x cpu freq")
                limiter.reset()
        finally:
            if limiter is not None: limiter.reset()


class CMD_gmark:
    """GravityMark benchmark for OpenGL and Vulkan on all platforms"""

    def __init__(self):
        self.gmark_root = HOME + "/gravity_mark"
        if not os.path.exists(self.gmark_root):
            CMD_download().download_gravitymark()
    
    def fix_me(self):
        subprocess.run(["bash", "-lic", """
            sudo apt install -y clang build-essential pkg-config libgtk2.0-dev libglib2.0-dev libpango1.0-dev libatk1.0-dev libgdk-pixbuf-2.0-dev 
        """], check=True) 
    
    def run(self):
        self.exe = f"./GravityMark.{UNAME_M2}"
        self.args = "-temporal 1  -screen 0 -fps 1 -info 1 -sensors 1 -benchmark 1 -vk -fullscreen 1 -vsync 0 -close 1"
        self.workdir = f"{HOME}/gravity_mark/bin"
        subprocess.run(["bash", "-lic", f"{self.exe} {self.args}"], cwd=self.workdir, check=True) 


class CMD_3dmark:
    """3dMark benchmarks"""
    
    def run(self):
        test = horizontal_select("Select 3dMark test", ["steelNomad"], 0)
        if not os.path.exists(HOME + f"/3dMark_{test}"):
            CMD_download().download_3dMark(test)
        headless = horizontal_select("Is this a headless system", ["yes", "no"], 1, return_bool=True)
        subprocess.run(["bash", "-lic", rf"""
            cd $HOME/3dMark_{test}/engine 
            ./build/bin/dev_player --asset_root=../assets_desktop --config=configs/gt1.json {"--headless" if headless else ""} | tee /tmp/log 
            fps=$(cat /tmp/log | grep 'FPS result:' | awk -F': ' '{{ print $2 }}')
            echo "$fps FPS"
        """], check=True) 


class CMD_microbench:
    """Nvidia's Vulkan Microbenchmark"""

    def __init__(self):
        self.nvperf_vulkan = f"{HOME}/nvperf_vulkan"
        if not os.path.exists(self.nvperf_vulkan):
            CMD_download().download_microbench() 
    
    def run(self):
        device = horizontal_select("Select GPU device", ["0", "1", "2", "<input>"], 0)
        test = horizontal_select("Select test", ["all", "subset", "<input>"], 0)
        self.run_with_config(device=device, test=test)

    def get_device_list(self):
        output = subprocess.run(["bash", "-lic", rf"""
            {self.nvperf_vulkan} -h | grep 'VK device name' | grep -v 'llvmpipe' | awk -F'name' '{{print $2}}'
        """], check=True, text=True, capture_output=True).stdout
        return output.splitlines()

    def run_with_config(self, device, test):
        subprocess.run(["bash", "-lic", f"rm -f {HOME}/microbench.raw.txt; {self.nvperf_vulkan} -nullDisplay -device {device} {test} | tee {HOME}/microbench.raw.txt"], check=True)
        self.print_csv(f"{HOME}/microbench.raw.txt", f"{HOME}/microbench_{datetime.now().strftime('%Y_%m%d_%H%M')}.csv")
        
    def print_csv(self, logpath, csvpath): 
        with open(csvpath, mode="w") as csvfile:
            csvfile.write(f"Test_case,Tags,Value\n")
            with open(logpath, mode="r") as logfile:
                for line in logfile.readlines():
                    line = line.strip()
                    if line.startswith("[Test_case:"):
                        middle = line[1:-1].split(": ")[1].split(" = ")[0]
                        name = middle.split("|")[0]  if "|" in middle else middle 
                        tags = middle.split("|")[1:] if "|" in middle else ""
                        result = line[1:-1].split(": ")[1].split(" = ")[1]
                        csvfile.write(f"{name} ({result.split()[1]}),{' | '.join(tags)},{result.split()[0]}\n")
                        continue
        print(f"Generated {csvpath}")
                    
                    
if __name__ == "__main__":
    try:
        with Timer():
            check_global_env() 
            cmd = main_cmd_prompt()
            cmd = globals().get(f"CMD_{cmd}")()
            cmd.run()
    except InterruptedError:
        sys.exit(0)
    except Exception:
        sys.stderr.write(traceback.format_exc()) 
    horizontal_select("Press [Enter] to exit")
