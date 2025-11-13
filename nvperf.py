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
        if ctypes.windll.shell32.IsUserAnAdmin() == 0:
            cmdline = subprocess.list2cmdline([os.path.abspath(sys.argv[0])] + [arg for arg in sys.argv[1:] if arg != "--admin"])
            ctypes.windll.shell32.ShellExecuteW(None, "runas", sys.executable, cmdline, None, 1)
            sys.exit(0)
            
        names = r"\b(" + "|".join(re.escape(k) for k in (*self.hosts, "wanliz")) + r")\b"
        mappings = "\n".join(f"{ip} {name}" for name, ip in self.hosts.items())
        subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", rf"""
            Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters' -Name 'AllowInsecureGuestAuth' -Type DWord -Value 1
            $ErrorActionPreference = 'Stop'
                        
            Write-Host "Checking WSL2 status"
            if (wsl -l -v 2>$null | Select-Object -Skip 1 | ForEach-Object {{ ($_ -replace '\x00','' -split '\s+')[-1] }} | Where-Object {{ $_ -eq '2' }} | Select-Object -First 1) {{ "WSL2 present" }} else {{ 
                Write-Host "No WSL2 distros, install it first" -ForegroundColor Yellow
                exit(1)
            }}
            $wsl_cfg="$env:USERPROFILE\.wslconfig"
            if (Test-Path $wsl_cfg) {{
                if (-not (Select-String -Path $wsl_cfg -SimpleMatch -Pattern 'networkingMode=mirrored' -Quiet)) {{
                    Write-Host "Please add 'networkingMode=mirrored' to $wsl_cfg first" -ForegroundColor Yellow
                    exit(1)
                }}
            }} else {{ 
                "[wsl2]`r`nnetworkingMode=mirrored" | Set-Content $wsl_cfg 
                Write-Host ""Restart WSL for the changes of ~/.wslconfig to take effect" -ForegroundColor Yellow
            }}
                        
            function Enable-SSH-Server-on-Windows {{ 
                Write-Host "`r`nChecking SSH server status"
                $cap = Get-WindowsCapability -Online -Name OpenSSH.Server* | Select-Object -First 1
                if ($cap.State -ne 'Installed') {{ 
                    Add-WindowsCapability -Online -Name $cap.Name 
                    Set-Service -Name sshd -StartupType Automatic
                }}
                $cap = Get-WindowsCapability -Online -Name OpenSSH.Client* | Select-Object -First 1
                if (-not $cap -or $cap.State -ne 'Installed') {{ 
                    Add-WindowsCapability -Online -Name $cap.Name 
                    Set-Service -Name ssh-agent -StartupType Automatic
                }}
                if ((Get-Service sshd).Status -ne 'Running') {{ Start-Service sshd }}
                if ((Get-Service ssh-agent -ErrorAction Stop).Status -ne 'Running') {{ Start-Service ssh-agent }}
                if (-not ((Get-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -ErrorAction SilentlyContinue).DefaultShell -match '\\(powershell|pwsh)\.exe$')) {{
                    New-Item -Path 'HKLM:\SOFTWARE\OpenSSH' -Force | Out-Null
                    New-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name 'DefaultShell' -PropertyType String -Value 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -Force | Out-Null
                    Restart-Service sshd -Force
                }}
                Start-Sleep -Seconds 1
                $tcp   = Test-NetConnection -ComputerName localhost -Port 22 -WarningAction SilentlyContinue
                $state = if ($tcp.TcpTestSucceeded) {{ 'LISTENING' }} else {{ 'NOT LISTENING' }}
                $sshd  = Get-Service sshd
                "SSH server status: {{0}} | Startup: {{1}} | Port 22: {{2}}" -f $sshd.Status, $sshd.StartType, $state
            }}
                        
            function Disable-SSH-Server-on-Windows-and-Enable-on-WSL {{
                $svc = Get-Service -Name sshd -ErrorAction SilentlyContinue
                if ($svc -and $svc.Status -eq 'Running') {{
                    Write-Host "`r`nDisable SSH server on Windows"
                    Stop-Service -Name sshd -Force
                    Set-Service -Name sshd -StartupType Disabled
                }}
                Write-Host "`r`nChecking SSH server on WSL (ensure Auto-Start)"
                $Action  = New-ScheduledTaskAction -Execute "wsl.exe" -Argument "-d Ubuntu -u root -- true"
                $Trigger = New-ScheduledTaskTrigger -AtStartup
                if (-not (Get-ScheduledTask -TaskName "WSL_Autostart_Ubuntu" -ErrorAction SilentlyContinue)) {{
                    Register-ScheduledTask -TaskName "WSL_Autostart_Ubuntu" -Action $Action -Trigger $Trigger -RunLevel Highest
                }}
            }}
            
            Disable-SSH-Server-on-Windows-and-Enable-on-WSL

            Write-Host "`r`nChecking PATH environment variables"
            $want = @('C:\Program Files', $env:LOCALAPPDATA.TrimEnd('\'))
            $cur  = ($env:Path -split ';') | ? {{ $_ }} | % {{ $_.Trim('"').TrimEnd('\') }}
            $miss = $want | % {{ $_.Trim('"').TrimEnd('\') }} | ? {{ $cur -notcontains $_ }}
            if ($miss) {{
                $env:Path = ($cur + $miss) -join ';'
                $user = ([Environment]::GetEnvironmentVariable('Path','User') -split ';') | ? {{ $_ }} | % {{ $_.Trim('"').TrimEnd('\') }}
                [Environment]::SetEnvironmentVariable('Path', ($user + ($miss | ? {{ $user -notcontains $_ }})) -join ';', 'User')
            }}
                        
            Write-Host "`r`nChecking classic context menu"
            $k = 'HKCU:\Software\Classes\CLSID\{{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}}\InprocServer32'
            if (-not (Test-Path $k) -or ((Get-Item $k).GetValue('', $null) -ne '')) {{
                New-Item $k -Force | Out-Null
                Set-Item  $k -Value ''
                Stop-Process -Name explorer -Force
                Start-Process explorer.exe
            }}

            Write-Host "`r`nChecking C:\Windows\System32\drivers\etc\hosts"
            $hostsfile = 'C:\Windows\System32\drivers\etc\hosts'
            $pattern = '({names})'
            if ((Get-Item -LiteralPath $hostsfile).Attributes -band [IO.FileAttributes]::ReadOnly) {{
                attrib -R $hostsfile
            }}
            $lines = Get-Content -LiteralPath $hostsfile -Encoding ASCII -ErrorAction SilentlyContinue 
            if ($null -eq $lines) {{ $lines = @() }}
            $content_old = $lines | Where-Object {{ ($_ -notmatch $pattern) -and ($_.Trim() -ne '') }}
            $content_new = ($content_old + "" + "`n# --- wanliz ---`n{mappings}`n") -join "`r`n"
            [IO.File]::WriteAllText($hostsfile, $content_new + "`r`n", [System.Text.Encoding]::ASCII)

            Write-Host "`r`nAllow all users to run .ps1 scripts"
            Set-ExecutionPolicy Bypass -Scope LocalMachine -Force

            Write-Host "`r`nDisable 'Only allow Windows Hello sign-in'"
            Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device' -Name 'DevicePasswordLessBuildVersion' -Type DWord -Value 0

            Write-Host "`r`nDisable Windows Firewall for all profiles"
            Set-NetFirewallProfile -Profile Domain,Private,Public -Enabled False
            Get-NetFirewallProfile | Select-Object Name, Enabled

            Write-Host "`r`nChecking context menu items"
            Invoke-WebRequest "https://raw.githubusercontent.com/wanlizhu/wanliz/main/WhoLocks.ps1" -OutFile "C:\Program Files\WhoLocks.ps1"
            $root = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Classes', $true)
            foreach ($sub in @('*\shell\WhoLocks','Directory\shell\WhoLocks')) {{
                $k = $root.CreateSubKey($sub)
                $k.SetValue('MUIVerb','Who locks this?',[Microsoft.Win32.RegistryValueKind]::String)
                $k.SetValue('Icon','%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe',[Microsoft.Win32.RegistryValueKind]::String)
                $k.SetValue('HasLUAShield','',[Microsoft.Win32.RegistryValueKind]::String)
                $cmd = 'cmd.exe /c start "" "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "C:\Program Files\WhoLocks.ps1" "%1"'
                ($k.CreateSubKey('command')).SetValue('', $cmd, [Microsoft.Win32.RegistryValueKind]::String)
                $k.Close()
            }}
            $root.Close()
        """], check=True)
        
    def config_linux_host(self):
        subprocess.run([
            "bash", "-lic", rf"""
            if [[ -z $(which sudo) ]]; then 
                apt update -y 
                apt install -y sudo 
            fi 
            if [[ ! -z $USER ]]; then 
                if ! sudo grep -qxF "$USER ALL=(ALL) NOPASSWD:ALL" /etc/sudoers; then 
                    echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee -a /etc/sudoers &>/dev/null
                fi
            fi 
            if [[ ! -f ~/.passwd ]]; then 
                read -r -s -p "OpenSSL Password: " passwd; echo
                echo -n "$passwd" > ~/.passwd    
                echo "Updated ~/.passwd"       
            fi
                        
            declare -A package_list=(
                [jq]=jq
                [rsync]=rsync
                [vim]=vim
                [curl]=curl
                [screen]=screen
                [sshpass]=sshpass
                [lsof]=lsof
                [xhost]=x11-xserver-utils
                [xrandr]=x11-xserver-utils
                [xset]=x11-utils
                [xdpyinfo]=x11-utils
                [openbox]=openbox
                [obconf]=obconf
                [x11vnc]=x11vnc
                [glxinfo]=mesa-utils
                [X]=xserver-xorg-core
                [mount.nfs]=nfs-common
                [showmount]=nfs-common
                [mount.cifs]=cifs-utils
                [exportfs]=nfs-kernel-server
                [smbd]=samba
                [testparm]=samba-common-bin
                [pdbedit]=samba-common-bin
                [smbpasswd]=samba-common-bin
            )
            echo "Updating APT package lists ..."
            sudo apt update &>/dev/null || true 
            for cmd in "${{!package_list[@]}}"; do
                if ! command -v "$cmd" &>/dev/null; then
                    pkg="${{package_list[$cmd]}}"
                    echo -n "Installing $pkg ... "
                    sudo apt install -y "$pkg" >/dev/null 2>/tmp/err && echo "[OK]" || {{ 
                        echo "[FAILED]"
                        cat /tmp/err 
                    }}
                fi
            done
            
            if ! dpkg -s openssh-server >/dev/null 2>&1; then
                read -p "Install SSH server? (Y/n): " install_ssh
                if [[ -z $install_ssh || "$install_ssh" == "y" ]]; then 
                    sudo apt install -y openssh-server
                    if [[ "$(cat /proc/1/comm 2>/dev/null)" == "systemd" ]] && command -v systemctl >/dev/null 2>&1; then
                        sudo systemctl enable ssh || true
                        sudo systemctl restart ssh || true
                    fi
                fi
            fi

            if [[ -z $(which nvperf.py) ]]; then 
                echo -e '\nexport PATH="$PATH:$HOME/wanliz"' >> ~/.bashrc
                echo "Updated ~/.bashrc"
            fi 
                        
            if [[ ! -f ~/.screenrc ]]; then 
                printf "%s\n" \
                    "startup_message off" \
                    "termcapinfo xterm*|xterm-256color* ti@:te@" \
                    "defscrollback 100000" \
                    "defmousetrack off" \
                    "hardstatus alwaysfirstline" \
                    "hardstatus string '%{{= bW}} [SCREEN %H] %=%-Lw %n:%t %+Lw %=%Y-%m-%d %c '" \
                >> ~/.screenrc
                echo "Updated ~/.screenrc"
            fi 
        """], check=True)

        # Add SSH/GTL keys 
        missing_keys = False
        if not os.path.exists(f"{HOME}/.ssh/id_ed25519"): missing_keys = True
        if not os.path.exists(f"{HOME}/.gtl_api_key"): missing_keys = True
        if missing_keys:
            choice = horizontal_select("Do you want to install registered keys", ["yes", "no"], 0, return_bool=True)
            if choice: subprocess.run(["bash", "-lic", rf"""
                if [[ ! -f ~/.ssh/id_ed25519 ]]; then 
                    cipher_prv='U2FsdGVkX1/M3Vl9RSvWt6Nkq+VfxD/N9C4jr96qvbXsbPfxWmVSfIMGg80m6g946QCdnxBxrNRs0i9M0mijcmJzCCSgjRRgE5sd2I9Buo1Xn6D0p8LWOpBu8ITqMv0rNutj31DKnF5kWv52E1K4MJdW035RHoZVCEefGXC46NxMo88qzerpdShuzLG8e66IId0kEBMRtWucvhGatebqKFppGJtZDKW/W1KteoXC3kcAnry90H70x2fBhtWnnK5QWFZCuoC16z+RQxp8p1apGHbXRx8JStX/om4xZuhl9pSPY47nYoCAOzTfgYLFanrdK10Jp/huf40Z0WkNYBEOH4fSTD7oikLugaP8pcY7/iO0vD7GN4RFwcB413noWEW389smYdU+yZsM6VNntXsWPWBSRTPaIEjaJ0vtq/4pIGaEn61Tt8ZMGe8kKFYVAPYTZg/0bai1ghdA9CHwO9+XKwf0aL2WalWd8Amb6FFQh+TlkqML/guFILv8J/zov70Jxz/v9mReZXSpDGnLKBpc1K1466FnlLJ89buyx/dh/VXJb+15RLQYUkSZou0S2zxo'  
                    mkdir -p ~/.ssh
                    echo "$cipher_prv" | openssl enc -d -aes-256-cbc -pbkdf2 -a -pass "pass:$(cat ~/.passwd)" > ~/.ssh/id_ed25519
                    chmod 600 ~/.ssh/id_ed25519
                    echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHx7hz8+bJjBioa3Rlvmaib8pMSd0XTmRwXwaxrT3hFL wanliz@Enzo-MacBook' > ~/.ssh/id_ed25519.pub
                    chmod 644 ~/.ssh/id_ed25519.pub
                    echo "Updated ~/.ssh/id_ed25519"
                fi 
                if [[ ! -f ~/.gtl_api_key ]]; then 
                    cipher='U2FsdGVkX18BU0ZpoGynLWZBV16VNV2x85CjdpJfF+JF4HhpClt/vTyr6gs6GAq0lDVWvNk7L7s7eTFcJRhEnU4IpABfxIhfktMypWw85PuJCcDXOyZm396F02KjBRwunVfNkhfuinb5y2L6YR9wYbmrGDn1+DjodSWzt1NgoWotCEyYUz0xAIstEV6lF5zedcGwSzHDdFhj3hh5YxQFANL96BFhK9aSUs4Iqs9nQIT9evjinEh5ZKNq5aJsll91czHS2oOi++7mJ9v29sU/QjaqeSWDlneZj4nPYXhZRCw='
                    echo "$cipher" | openssl enc -d -aes-256-cbc -pbkdf2 -a -pass "pass:$(cat ~/.passwd)" > ~/.gtl_api_key
                    chmod 500 ~/.gtl_api_key
                    echo "Updated ~/.gtl_api_key"
                fi 
            """], check=False)

        def missing_or_empty_dir(pathstr):
            path = Path(pathstr)
            if path.exists():
                return not any(path.iterdir())
            return True 

        # Mount folders 
        mount_dirs = []
        if missing_or_empty_dir("/mnt/linuxqa"): mount_dirs.append(["linuxqa.nvidia.com:/storage/people", "/mnt/linuxqa"])
        if missing_or_empty_dir("/mnt/data"): mount_dirs.append(["linuxqa.nvidia.com:/storage/data", "/mnt/data"])
        if missing_or_empty_dir("/mnt/builds"): mount_dirs.append(["linuxqa.nvidia.com:/storage3/builds", "/mnt/builds"])
        if missing_or_empty_dir("/mnt/dvsbuilds"): mount_dirs.append(["linuxqa.nvidia.com:/storage5/dvsbuilds", "/mnt/dvsbuilds"])
        if missing_or_empty_dir("/mnt/wanliz_sw_linux"): mount_dirs.append(["office:/wanliz_sw_linux", "/mnt/wanliz_sw_linux"])
        if mount_dirs:
            choice = horizontal_select("Do you want to mount linuxqa folders", ["yes", "no"], 0, return_bool=True)
            if choice: 
                mount_cmds = [f"sudo mkdir -p {item[1]}; sudo timeout 3 mount -t nfs {item[0]} {item[1]} && echo 'Mounted {item[1]}' || echo 'Failed to mount {item[1]}'" for item in mount_dirs]
                subprocess.run(["bash", "-lic", "\n".join(mount_cmds) + "\n"], check=False)
        
        # Add known host IPs (hostname -> IP)
        try:
            hosts_str = Path("/etc/hosts").read_text(encoding="utf-8")
            if not all([f"{ip}\t{name}" in hosts_str for name, ip in self.hosts.items()]):
                update_hosts = horizontal_select("Do you want to update /etc/hosts", ["yes", "no"], 0, return_bool=True)
                if update_hosts:
                    hosts_out = []
                    for line in Path("/etc/hosts").read_text().splitlines():
                        if line.strip().startswith("#"):  continue
                        if any(name in self.hosts for name in line.split()[1:]): continue 
                        hosts_out.append(line)
                    hosts_out += [f"{ip}\t{name}" for name, ip in self.hosts.items()]
                    subprocess.run(["bash", "-lic", rf"""
                        echo '{"\n".join(hosts_out) + "\n"}' | sudo tee /etc/hosts >/dev/null 
                    """], check=True)
        except Exception:
            print("Failed to update /etc/hosts")


class CMD_info:
    """Get GPU HW and driver info"""
    
    def run(self):
        if platform.system() == "Linux":
            self.linux_info()
        elif platform.system() == "Windows":
            self.windows_info()

    def windows_info(self):
        subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", rf"""
            nvidia-smi --query-gpu=name,driver_version,pci.bus_id,memory.total,clocks.gr --format=csv | ConvertFrom-Csv |  Format-Table -AutoSize
            nvidia-smi -q | Select-String 'GSP Firmware Version'
        """], check=True)

    def linux_info(self):
        subprocess.run(["bash", "-lic", rf"""
            export DISPLAY=:0  
            if [[ -z $(which jq) ]]; then 
                sudo apt install -y jq &>/dev/null 
            fi 
            echo "X server info:"
            if timeout 2s bash -lc 'command -v xdpyinfo >/dev/null && xdpyinfo >/dev/null 2>&1 || xset q >/dev/null 2>&1'; then 
                echo "X(:0) is online"
                echo "DISPLAY=:$DISPLAY"
                echo "XDG_SESSION_TYPE=:$XDG_SESSION_TYPE"
                xrandr | grep current
                glxinfo | grep -i 'OpenGL renderer'
            else 
                echo "X(:0) is down or unauthorized"
            fi 
            echo -e "\nList GPU devices:"
            nvidia-smi --query-gpu=index,pci.bus_id,name,compute_cap --format=csv,noheader | while IFS=, read -r idx bus name cc; do
                bus=$(echo "$bus" | awk '{{$1=$1}};1' | sed 's/^00000000/0000/' | tr 'A-Z' 'a-z')
                sys="/sys/bus/pci/devices/$bus"
                node=$(cat "$sys/numa_node" 2>/dev/null || echo -1)         # -1 means no NUMA info
                cpus=$(cat "$sys/local_cpulist" 2>/dev/null || echo '?')
                printf "GPU: %s    Name: %s    PCI: %s    NUMA node: %s    CPUs: %s\n" "$idx" "$name" "$bus" "$node" "$cpus"
            done
            if [[ -f /mnt/linuxqa/wanliz/vk-physdev-info.$(uname -m) ]]; then 
                /mnt/linuxqa/wanliz/vk-physdev-info.$(uname -m) | jq -s .
            fi 
            echo -e "\nDriver info:"
            nvidia-smi | grep "Driver Version"
            nvidia-smi -q | grep -i 'GSP Firmware Version' | sed 's/^[[:space:]]*//'
            echo -e "\nList PIDs using nvidia module:"
            sudo lsof -w -n /dev/nvidia* | awk 'NR>1{{print $2}}' | sort -un | while read -r pid; do
                printf "PID=%-7s %s\n" "$pid" "$(tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null || ps -o args= -p "$pid")"
            done
        """], check=False)


class CMD_ip:
    """My public IP to remote"""

    def run(self):
        print(self.public_ip_to("1.1.1.1"))

    def public_ip_to(self, remote, missing_OK=True):
        output = subprocess.run(["bash", "-lic", rf"ip -4 route get \"$(getent ahostsv4 {remote} | awk 'NR==1{{print $1}}')\" | sed -n 's/.* src \([0-9.]\+\).*/\1/p'"], check=True, text=True, capture_output=True)
        if output.returncode != 0:
            if missing_OK: return None
            else: raise RuntimeError(f"{remote} is not reachable") 
        return output.stdout 

    
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
        subcmd = horizontal_select("Select git-emu subcmd", ["status", "pull", "stash"], 0)
        if subcmd == "status": self.status()
        elif subcmd == "pull": self.pull()
        elif subcmd == "stash": self.stash()

    def status(self):
        reconcile = horizontal_select("Do you want to run p4 reconcile to collect changes", ["yes", "no"], 1, return_bool=True)
        subprocess.run(["bash", "-lic", rf"""
            echo "=== Files Opened for Edit ==="
            ofiles=$(p4 opened -C $P4CLIENT //$P4CLIENT/...)
            if [[ ! -z $ofiles ]]; then
                echo $ofiles
            fi 
            if (( {1 if reconcile else 0} )); then 
                echo 
                echo "=== Files Not Tracked ==="
                afiles=$(p4 reconcile -n -a $P4ROOT/... 2>/dev/null || true)
                if [[ ! -z $afiles ]]; then 
                    echo "$afiles"     
                fi  
                echo 
                echo "=== Files Deleted ==="
                dfiles=$(p4 reconcile -n -d $P4ROOT/... 2>/dev/null || true)
                if [[ ! -z $dfiles ]]; then 
                    echo "$dfiles"   
                fi  
            fi 
        """], cwd=self.p4root, check=True)

    def pull(self):
        force = horizontal_select("Do you want to run force pull", ["yes", "no"], 1, return_bool=True)
        subprocess.run(["bash", "-lic", rf"""
            time p4 sync {"-f" if force else ""}
            resolve_files=$(p4 resolve -n $P4ROOT/... 2>/dev/null)
            if [[ ! -z $resolve_files ]]; then 
                echo "Need resolve, trying auto-merge"
                p4 resolve -am $P4ROOT/... 
                conflict_files=$(p4 resolve $P4ROOT/... 2>/dev/null)
                if [[ ! -z $conflict_files ]]; then 
                    echo "$(echo $conflict_files | wc -l) conflict files remain [Manual Merge]"
                    echo $conflict_files
                else
                    echo "No manual resolved needed"
                fi
            else
                echo "No resolves needed"
            fi 
        """], cwd=self.p4root, check=True)

    def stash(self):
        name = horizontal_select("Select stash name", [f"stash_{datetime.now().astimezone():%Y-%m-%d_%H-%M-%S}", "<input>"], 0)
        subprocess.run(["bash", "-lic", rf"""
            p4 reconcile -e -a -d $P4ROOT/... >/dev/null || true
            p4 change -o /tmp/stash
            sed -i "s|<enter description here>|STASH: $(date '+%F %T')" /tmp/stash 
            cl=$(p4 change -i </tmp/stash | awk '/^Change/ {{print $2}}')
            p4 reopen -c $cl $P4ROOT/... >/dev/null || true 
            p4 shelve -f -c $cl >/dev/null 
            echo "Stashed into CL $cl"
        """], cwd=self.p4root, check=True)


class CMD_sshkey:
    """Set up SSH key and copy to remote"""

    def run(self):
        host = horizontal_select("Host IP")
        user = horizontal_select("User", ["WanliZhu", "wanliz", "nvidia", "<input>"], 0)
        self.copy_to(host, user)

    def copy_to(self, host, user, passwd=None):
        subprocess.run(["bash", "-lic", rf"""
            if [[ ! -f ~/.ssh/id_ed25519 ]]; then 
                if [[ ! -f ~/.passwd ]]; then 
                    read -r -s -p "OpenSSL Password: " passwd; echo
                    echo -n "$passwd" > ~/.passwd    
                    echo "Updated ~/.passwd"       
                fi
                cipher_prv='U2FsdGVkX1/M3Vl9RSvWt6Nkq+VfxD/N9C4jr96qvbXsbPfxWmVSfIMGg80m6g946QCdnxBxrNRs0i9M0mijcmJzCCSgjRRgE5sd2I9Buo1Xn6D0p8LWOpBu8ITqMv0rNutj31DKnF5kWv52E1K4MJdW035RHoZVCEefGXC46NxMo88qzerpdShuzLG8e66IId0kEBMRtWucvhGatebqKFppGJtZDKW/W1KteoXC3kcAnry90H70x2fBhtWnnK5QWFZCuoC16z+RQxp8p1apGHbXRx8JStX/om4xZuhl9pSPY47nYoCAOzTfgYLFanrdK10Jp/huf40Z0WkNYBEOH4fSTD7oikLugaP8pcY7/iO0vD7GN4RFwcB413noWEW389smYdU+yZsM6VNntXsWPWBSRTPaIEjaJ0vtq/4pIGaEn61Tt8ZMGe8kKFYVAPYTZg/0bai1ghdA9CHwO9+XKwf0aL2WalWd8Amb6FFQh+TlkqML/guFILv8J/zov70Jxz/v9mReZXSpDGnLKBpc1K1466FnlLJ89buyx/dh/VXJb+15RLQYUkSZou0S2zxo'  
                mkdir -p ~/.ssh
                echo "$cipher_prv" | openssl enc -d -aes-256-cbc -pbkdf2 -a -pass "pass:$(cat ~/.passwd)" > ~/.ssh/id_ed25519
                chmod 600 ~/.ssh/id_ed25519
                echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHx7hz8+bJjBioa3Rlvmaib8pMSd0XTmRwXwaxrT3hFL wanliz@Enzo-MacBook' > ~/.ssh/id_ed25519.pub
                chmod 644 ~/.ssh/id_ed25519.pub
                echo "Updated ~/.ssh/id_ed25519"
            fi 
            {f"sshpass -p '{passwd}'" if passwd else ""} ssh-copy-id -o StrictHostKeyChecking=accept-new {user}@{host}
            ssh {user}@{host} "echo '~/.ssh/id_ed25519 works'"
        """], check=False)


class CMD_upload:
    """Upload Linux local folder to Windows SSH host"""
    
    def run(self):
        hostname = socket.gethostname()
        user, host, passwd = self.get_windows_host()
        src = horizontal_select("Select local folder", [f"{HOME}:NoRecur", "<input>"], 0)
        if src == f"{HOME}:NoRecur":
            excludes = ["*/", ".*", "*.deb", "*.run", "*.tar", "*.tar.gz", "*.tgz", "*.zip", "*.so", "perfdebug", "sandbag-tool", "LockToRatedTdp"]
            subprocess.run(["bash", "-lic", rf"""
                sshpass -p '{passwd}' rsync -lth --info=progress2 -e 'ssh -o StrictHostKeyChecking=accept-new' {" ".join(f"--exclude='{x}'" for x in excludes)} {HOME}/* {user}@{host}:/mnt/d/{USER}@{hostname}/
            """], check=True)
        else:
            subprocess.run(["bash", "-lic", rf"""
                sshpass -p '{passwd}' rsync -lth --info=progress2 -e 'ssh -o StrictHostKeyChecking=accept-new' {src} {user}@{host}:/mnt/d/
            """], check=True)
        
    def get_windows_host(self):
        if os.path.exists(f"{HOME}/.upload_host"):
            text = Path(f"{HOME}/.upload_host").read_text(encoding="utf-8").rstrip("\n")
            user = text.split("@")[0]
            host = text.split("@")[1]
        else:
            host = horizontal_select("Host IP")
            user = horizontal_select("User", ["WanliZhu", "<input>"], 0)
        
        if os.path.exists(f"{HOME}/.passwd"):
            passwd_cipher = Path(f"{HOME}/.passwd").read_text(encoding="utf-8").rstrip("\n")
        else:
            passwd_cipher = getpass.getpass("OpenSSL Password: ")
            Path(f"{HOME}/.passwd").write_text(passwd_cipher, encoding="utf-8")
            
        passwd = getpass.getpass("SSH Password: ")
        if self.test(user, host, passwd):
            Path(f"{HOME}/.upload_host").write_text(f"{user}@{host}", encoding="utf-8")
            CMD_sshkey().copy_to(host=host, user=user, passwd=passwd)
        else:
            Path(f"{HOME}/.upload_host").unlink(missing_ok=True)
            print("Authentication failed")
            return self.get_windows_host()

        return user, host, passwd 
        
    def test(self, user, host, passwd):
        sshpass = f"sshpass -p '{passwd}'" if passwd else ""
        print(f"Authenticating {user}@{host} with {'password' if passwd else 'keys'}")
        output = subprocess.run(["bash", "-lic", rf"""
            if [[ -z $(which sshpass) ]]; then sudo apt install -y sshpass &>/dev/null; fi 
            {sshpass} ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=3 {user}@{host} true
        """], check=False)
        return output.returncode == 0 


class CMD_share:
    """Share a Linux folder via both SMB and NFS"""
    
    def run(self):
        subcmd = horizontal_select("Select subcmd", ["create", "list"], 0)
        if subcmd == "share":
            path = horizontal_select("Select or input folder to share", [HOME, "<input>"], 0)
            path = Path(path).resolve()
            if not (path.exists() and path.is_dir()):
                raise RuntimeError(f"Invalid path: {path}")
            self.share_via_nfs(path)
            self.share_via_smb(path)
        else:
            subprocess.run(["bash", "-lic", rf"""
                echo "=== NFS Exports ==="
                sudo exportfs -v | awk '/^\/|^\.\// {{print $1}}' | sort -u
                echo -e "\n=== SMB Exports ==="
                sudo testparm -s 2>/dev/null | awk '
                    /^\[.*\]$/ {{ sec=$0; gsub(/^\[|\]$/,"",sec); next }}
                    tolower($0) ~ /^[ \t]*path[ \t]*=/ {{
                    p=$0; sub(/^[ \t]*path[ \t]*=[ \t]*/,"",p);
                    print sec "\t" p
                    }}' | grep -Ev '^(global|printers|print\$|homes)$' | column -t  
            """], check=True)

    def share_via_smb(self, path: Path):
        output = subprocess.run(["bash", "-lic", "testparm -s"], text=True, check=False, capture_output=True)
        if output.returncode != 0 and 'not found' in output.stderr:
            subprocess.run(["bash", "-lic", "sudo apt install -y samba-common-bin samba"], check=True)
            output = subprocess.run(["bash", "-lic", "testparm -s"], text=True, check=True, capture_output=True)

        for line in output.stdout.splitlines():
            if str(path) in line:
                print(f"{path} is sharing via SMB")
                return 
        
        shared_name = re.sub(r"[^A-Za-z0-9._-]","_", path.name) or "share"
        subprocess.run(["bash", "-lic", rf"""
            if ! pdbedit -L -u {getpass.getuser()} >/dev/null 2>&1; then
                sudo smbpasswd -a {getpass.getuser()}
            fi 
            if ! grep -q '^\[global\][[:space:]]*$' /etc/samba/smb.conf; then 
                echo '' | sudo tee -a /etc/samba/smb.conf >/dev/null
                echo '[global]' | sudo tee -a /etc/samba/smb.conf >/dev/null
                echo '   map to guest = Bad Password' | sudo tee -a /etc/samba/smb.conf >/dev/null
            fi 
            echo '' | sudo tee -a /etc/samba/smb.conf >/dev/null
            echo '[{shared_name}]' | sudo tee -a /etc/samba/smb.conf >/dev/null
            echo '   path = {path}' | sudo tee  -a /etc/samba/smb.conf >/dev/null
            echo '   public = yes' | sudo tee -a /etc/samba/smb.conf >/dev/null
            echo '   guest ok = yes' | sudo tee -a /etc/samba/smb.conf >/dev/null
            echo '   force user = {getpass.getuser()}' | sudo tee -a /etc/samba/smb.conf >/dev/null
            echo '   writable = yes' | sudo tee -a /etc/samba/smb.conf >/dev/null
            echo '   create mask = 0777' | sudo tee -a /etc/samba/smb.conf >/dev/null
            echo '   directory mask = 0777' | sudo tee -a /etc/samba/smb.conf >/dev/null
            sudo testparm -s || echo '/etc/samba/smb.conf is invalid'
            sudo systemctl enable --now smbd
            sudo systemctl restart smbd
        """], check=True)
        print(f"{path} is sharing via SMB as {shared_name}")

    def share_via_nfs(self, path: Path):
        output = subprocess.run(["bash", "-lic", "sudo exportfs -v"], text=True, check=False, capture_output=True)
        if output.returncode != 0 and 'not found' in output.stderr:
            subprocess.run(["bash", "-lic", "sudo apt install -y nfs-kernel-server"], check=True)
            output = subprocess.run(["bash", "-lic", "sudo exportfs -v"], text=True, check=True, capture_output=True)

        for line in output.stdout.splitlines():
            if line.strip().startswith(str(path) + " "):
                print(f"{path} is sharing via NFS")
                return
        
        subprocess.run(["bash", "-lic", rf"""
            echo '{path} *(rw,sync,insecure,no_subtree_check,no_root_squash)' | sudo tee -a /etc/exports >/dev/null 
            sudo exportfs -ra 
            sudo systemctl enable --now nfs-kernel-server
            sudo systemctl restart nfs-kernel-server
        """], check=True)
        print(f"{path} is sharing via NFS")


class CMD_mount:
    """Mount Windows or Linux shared folder"""
    
    def run(self):
        share_folder  = horizontal_select("Select shared folder", ["linuxqa", "builds", "data", "office:wanliz_sw_linux", "<input>"], 0)
        self.mount_one(share_folder)

    def mount_all(self, folders):
        for folder in folders:
            self.mount_one(folder)
        
    def mount_one(self, shared_folder):
        if platform.system() == "Linux":
            if shared_folder == "linuxqa": 
                fstype = "nfs"
                login_user = "wanliz"
                shared_folder = "linuxqa.nvidia.com:/storage/people"
                local_folder = "/mnt/linuxqa"
            elif shared_folder == "builds":
                fstype = "nfs"
                login_user = "wanliz"
                shared_folder = "linuxqa.nvidia.com:/qa/builds"
                local_folder = "/mnt/builds"
            elif shared_folder == "data":
                fstype = "nfs"
                login_user = "wanliz"
                shared_folder = "linuxqa.nvidia.com:/qa/data"
                local_folder = "/mnt/data"
            elif shared_folder == "office:wanliz_sw_linux":
                CMD_p4.setup_env()
                fstype = "nfs"
                login_user = "wanliz"
                shared_folder = f"office:{os.environ['P4ROOT']}"
                local_folder = f"/mnt{os.environ['P4ROOT']}"
            else:
                if shared_folder.startswith("//"): fstype = "cifs"  
                elif ":" in shared_folder: fstype = "nfs"
                login_user = horizontal_select("Select login user", ["wanliz", "WanliZhu", "<input>"], 0)
                local_folder = "/mnt/" + Path(shared_folder).name
            subprocess.run(["bash", "-lic", f"""
                if ! command -v mount.cifs >/dev/null 2>&1; then
                    sudo apt install -y cifs-utils 2>/dev/null 
                fi
                if ! command -v mount.nfs >/dev/null 2>&1; then
                    sudo apt install -y nfs-common 2>/dev/null 
                fi 
                if ! mountpoint -q {local_folder}; then  
                    sudo mkdir -p {local_folder} &&
                    sudo mount -t {fstype} {f"-o username={login_user}" if login_user else ""} {shared_folder} {local_folder}
                fi
            """], check=True)
        elif platform.system() == "Windows":
            if ctypes.windll.shell32.IsUserAnAdmin() == 0:
                cmdline = subprocess.list2cmdline([os.path.abspath(sys.argv[0])] + [arg for arg in sys.argv[1:] if arg != "--admin"])
                ctypes.windll.shell32.ShellExecuteW(None, "runas", sys.executable, cmdline, None, 1)
                sys.exit(0)
            shared_folder = shared_folder.strip().replace("/", "\\")
            shared_folder = shared_folder.rstrip("\\")
            unc_path = shared_folder if shared_folder.startswith("\\\\") else ("\\\\" + shared_folder.lstrip("\\")) 
            drive = horizontal_select("Mount to drive", ["N", "X", "Y", "Z"], 3)
            user = horizontal_select("Target user", ["nvidia", "wanliz", "wzhu", "<input>"], 0)
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
        
        self.branch = f"{os.environ['P4ROOT']}/rel/gpu_drv/r580/r580_00"
        self.targets = {
            ".":          { "args": "", "workdir": "." },
            "drivers":    { "args": "drivers dist",   "workdir": f"{self.branch}" },
            "opengl":     { "args": "", "workdir": f"{self.branch}/drivers/OpenGL" },
            "microbench": { "args": "", "workdir": f"{os.environ['P4ROOT']}/apps/gpu/drivers/vulkan/microbench" },
            "inspect-gpu-page-tables":  { "args": "", "workdir": f"{os.environ['P4ROOT']}/pvt/aritger/apps/inspect-gpu-page-tables" }
        }

        target = horizontal_select("Build target", self.targets.keys(), 0)
        config = horizontal_select("Target config", ["develop", "debug", "release"], 0)
        arch   = horizontal_select("Target architecture", ["amd64", "aarch64"], 0 if UNAME_M == "x86_64" else 1)
        self.run_with_config(target, config, arch)

    def unix_build_nvmake(self, target, config, arch):
        nvmake_cmd = " ".join([x for x in [
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
            self.targets[target]['args'],
            "linux", 
            f"{arch}", 
            f"{config}"
        ] if x is not None and x != ""])
        subprocess.run(["bash", "-lic", rf"""
            cd {self.targets[target]['workdir']} && {nvmake_cmd} -j$(nproc) || {nvmake_cmd} -j1 >/dev/null 
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
            CMD_mount().mount_one("office:wanliz_sw_linux")
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
            CMD_mount().mount_one("linuxqa")

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
