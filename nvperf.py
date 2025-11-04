#!/usr/bin/env python3
import os
import sys
import time 
import datetime
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
import xml.etree.ElementTree as ET 
from pathlib import Path 
from datetime import timedelta
from time import perf_counter
from statistics import mean, stdev
from contextlib import suppress
if platform.system() == "Linux": 
    import termios
    import tty 
if platform.system() == "Windows":
    import msvcrt
pip_checked = False
for name in ["psutil"]:
    try:
        globals()[name] = importlib.import_module(name)
    except ModuleNotFoundError as e:
        if not pip_checked:
            if subprocess.run([sys.executable, "-m", "pip", "--version"], 
                           stdout=subprocess.DEVNULL, 
                           stderr=subprocess.DEVNULL, 
                           capture_output=True,
                           check=False).returncode != 0:
                subprocess.run(["sudo", "apt", "install", "-y", "python3-pip"], check=True)
            pip_checked = True
        package = name.split(".", 1)[0]
        subprocess.run([sys.executable, "-m", "pip", "install", package], check=True)


class CMD_info:
    def __str__(self):
        return "Get GPU HW and driver info"
    
    def run(self):
        subprocess.run([*BASH_CMD, "DISPLAY=:0 xrandr | grep current"], check=False)
        subprocess.run([*BASH_CMD, "DISPLAY=:0 glxinfo | grep -i 'OpenGL renderer'"], check=False)
        subprocess.run([*BASH_CMD, "nvidia-smi --query-gpu=name,driver_version,pci.bus_id,memory.total,clocks.gr | column -s, -t"], check=False)
        subprocess.run([*BASH_CMD, "nvidia-smi -q | grep -i 'GSP Firmware Version'"], check=False)
        for key in ["DISPLAY", "WAYLAND_DISPLAY", "XDG_SESSION_TYPE", "LD_PRELOAD", "LD_LIBRARY_PATH"] + sorted([k for k in os.environ if k.startswith("__GL_") or k.startswith("VK_")]):
            value = os.environ.get(key)
            print(f"{key}={value}") if value is not None else None 


class CMD_p4:
    def __init__(self):
        self.p4client = "wanliz_sw_linux"
        self.p4port = "p4proxy-sc.nvidia.com:2006"
        self.p4user = "wanliz"
        self.p4root = "/wanliz_sw_linux" if platform.system() == "Linux" else "/mnt/d/wanliz_sw_linux"
        self.p4ignore = HOME + "/.p4ignore"
        subprocess.run([*BASH_CMD, rf"""
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
            "P4CLIENT": self.p4client,
            "P4PORT": self.p4port,
            "P4USER": self.p4user, 
            "P4ROOT": self.p4root,
            "P4IGNORE": self.p4ignore
        })

    def __str__(self):
        return "Perforce command tool"
    
    def run(self):
        subcmd = horizontal_select("Select git-emu subcmd", ["status", "pull", "stash"], 0)
        if subcmd == "status": self.__status()
        elif subcmd == "pull": self.__pull()
        elif subcmd == "stash": self.__stash()

    def __status(self):
        reconcile = horizontal_select("Reconcile to check added/deleted files", ["yes", "no"], 1)
        subprocess.run([*BASH_CMD, rf"""
            echo "=== Files Opened for Edit ==="
            ofiles=$(p4 opened -C $P4CLIENT //$P4CLIENT/...)
            if [[ ! -z $ofiles ]]; then
                echo $ofiles
            fi 
            if [[ "{reconcile}" == "yes" ]]; then 
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

    def __pull(self):
        force = horizontal_select("Force pull", ["yes", "no"], 1)
        subprocess.run([*BASH_CMD, rf"""
            time p4 sync {"-f" if force == "yes" else ""}
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

    def __stash(self):
        name = horizontal_select("Select stash name", [f"stash_{datetime.datetime.now().astimezone():%Y-%m-%d_%H-%M-%S}", "<input>"], 0)
        subprocess.run([*BASH_CMD, rf"""
            p4 reconcile -e -a -d $P4ROOT/... >/dev/null || true
            p4 change -o /tmp/stash
            sed -i "s|<enter description here>|STASH: $(date '+%F %T')" /tmp/stash 
            cl=$(p4 change -i </tmp/stash | awk '/^Change/ {{print $2}}')
            p4 reopen -c $cl $P4ROOT/... >/dev/null || true 
            p4 shelve -f -c $cl >/dev/null 
            echo "Stashed into CL $cl"
        """], cwd=self.p4root, check=True)


class CMD_rsync:
    def __str__(self):
        return "Rsync remote folders to local"
    
    def run(self):
        src = horizontal_select("Rsync from source", ["p4:wanliz_sw_linux"], 0)
        if src == "p4:wanliz_sw_linux":
            self.__rsync_wanliz_sw_linux()

    def __rsync_wanliz_sw_linux(self):
        if platform.system() == "Windows":
            root = horizontal_select("Rsync to local folder", ["D:\\wanliz_sw_linux", "<input>"], 0)
            subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", rf"""
                New-Item -ItemType Directory -Force -Path "{root}" | Out-Null
                net use  "\\office\wanliz_sw_linux" /user:wanliz /persistent:no | Out-Null
                robocopy "\\office\wanliz_sw_linux" "{root}" /MIR /R:1 /W:1 /MT:32 /FFT /DCOPY:T /COPY:DT /A-:SH /XJ /NP /NFL /NDL /XD '.git' '_out' '.Trash-*' '.Trash' '.Trashes' '$RECYCLE.BIN' '.Spotlight-V*'
            """], check=False)
        else:
            root = horizontal_select("Rsync to local folder", [HOME + "/wanliz_sw_linux", "<input>"], 0)
            root = root[:-1] if root.endswith("/") else root 
            compress = horizontal_select("Rsync with compression", ["yes", "no"], 0)
            rsync_options = rsync_options = f"--compress --compress-choice=zstd --compress-level=7" if compress else ""
            ssh_options = "-e 'ssh -T -o Compression=no'" if compress else ""
            subprocess.run([*BASH_CMD, rf"""
                time rsync -ah --delete --delete-excluded --info=progress2 {rsync_options} {ssh_options} \
                    --exclude '.git/' \
                    --exclude '_out/' \
                    --exclude '.Trash-[0-9]*/' --exclude '.Trash/' --exclude '.Trashes/' \
                    --exclude '$RECYCLE.BIN/' --exclude '.Spotlight-V[0-9]*/' \
                    wanliz@office:/wanliz_sw_linux/ {root}
            """], check=True)


class CMD_config:
    def __str__(self):
        return "Configure test environment"
    
    def run(self):
        self.hosts = {
            "office": "172.16.179.143",
            "proxy": "10.176.11.106",
            "horizon5": "172.16.178.123",
            "horizon6": "172.16.177.182",
            "horizon7": "172.16.177.216",
            "n1x6": "10.31.40.241",
        }
        if platform.system() == "Windows":
            self.__config_windows_host()
        elif platform.system() == "Linux":
            self.__config_linux_host()

    def __config_windows_host(self):
        if ctypes.windll.shell32.IsUserAnAdmin() == 0:
            cmdline = subprocess.list2cmdline([os.path.abspath(sys.argv[0])] + [arg for arg in sys.argv[1:] if arg != "--admin"])
            ctypes.windll.shell32.ShellExecuteW(None, "runas", sys.executable, cmdline, None, 1)
            sys.exit(0)
            
        names = r"\b(" + "|".join(re.escape(k) for k in (*self.hosts, "wanliz")) + r")\b"
        mappings = "\n".join(f"{ip} {name}" for name, ip in self.hosts.items())
        subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", rf"""
            Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters' -Name 'AllowInsecureGuestAuth' -Type DWord -Value 1
            Write-Host "Updating C:\Windows\System32\drivers\etc\hosts"
            $ErrorActionPreference = 'Stop'
            $hostsfile = 'C:\Windows\System32\drivers\etc\hosts'
            $pattern = '({names})'
            if ((Get-Item -LiteralPath $hostsfile).Attributes -band [IO.FileAttributes]::ReadOnly) {{
                attrib -R $hostsfile
            }}
            $lines = Get-Content -LiteralPath $hostsfile -Encoding ASCII -ErrorAction SilentlyContinue 
            if ($null -eq $lines) {{ $lines = @() }}
            $content_old = $lines | Where-Object {{ ($_ -notmatch $pattern) -and ($_.Trim() -ne '') }}
            $content_new = ($content_old + "" + "`n# --- wanliz ---`n{mappings}`n") -join "`r`n"
            [IO.File]::WriteAllText($hostsfile, $content_new + "`r`n", [Text.Encoding]::ASCII)
        """], check=True)
        
    def __config_linux_host(self):
        # Enable no-password sudo
        subprocess.run([*BASH_CMD, rf"""
            if ! sudo grep -qxF "$USER ALL=(ALL) NOPASSWD:ALL" /etc/sudoers; then 
                echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee -a /etc/sudoers &>/dev/null
            fi
        """], check=True)
        print("No-password sudo \t [ ENABLED ]")

        # Mount required folders
        if not any(p.mountpoint == "/mnt/linuxqa" for p in psutil.disk_partitions(all=True)):
            subprocess.run("sudo mkdir -p /mnt/linuxqa", check=True, shell=True)
            subprocess.run("sudo apt install -y nfs-common cifs-utils &>/dev/null", check=True, shell=True)
            subprocess.run("sudo mount linuxqa.nvidia.com:/storage/people /mnt/linuxqa", check=True, shell=True)
        print("/mnt/linuxqa \t [ MOUNTED ]")

        # Add known host IPs (hostname -> IP)
        hosts_out = []
        for line in Path("/etc/hosts").read_text().splitlines():
            if line.strip().startswith("#"): 
                continue
            if any(name in self.hosts for name in line.split()[1:]):
                continue 
            hosts_out.append(line)
        hosts_out += [f"{ip}\t{name}" for name, ip in self.hosts.items()]
        Path("/tmp/hosts").write_text("\n".join(hosts_out) + "\n")
        subprocess.run("sudo install -m 644 /tmp/hosts /etc/hosts", check=True, shell=True)
        print("/etc/hosts \t [ UPDATED ]")

        if not os.path.exists(HOME + "/.ssh/id_ed25519"):
            cipher_prv = "U2FsdGVkX1/M3Vl9RSvWt6Nkq+VfxD/N9C4jr96qvbXsbPfxWmVSfIMGg80m6g946QCdnxBxrNRs0i9M0mijcmJzCCSgjRRgE5sd2I9Buo1Xn6D0p8LWOpBu8ITqMv0rNutj31DKnF5kWv52E1K4MJdW035RHoZVCEefGXC46NxMo88qzerpdShuzLG8e66IId0kEBMRtWucvhGatebqKFppGJtZDKW/W1KteoXC3kcAnry90H70x2fBhtWnnK5QWFZCuoC16z+RQxp8p1apGHbXRx8JStX/om4xZuhl9pSPY47nYoCAOzTfgYLFanrdK10Jp/huf40Z0WkNYBEOH4fSTD7oikLugaP8pcY7/iO0vD7GN4RFwcB413noWEW389smYdU+yZsM6VNntXsWPWBSRTPaIEjaJ0vtq/4pIGaEn61Tt8ZMGe8kKFYVAPYTZg/0bai1ghdA9CHwO9+XKwf0aL2WalWd8Amb6FFQh+TlkqML/guFILv8J/zov70Jxz/v9mReZXSpDGnLKBpc1K1466FnlLJ89buyx/dh/VXJb+15RLQYUkSZou0S2zxo"
            subprocess.run("mkdir -p ~/.ssh", check=True, shell=True)
            subprocess.run([*BASH_CMD, f"echo '{cipher_prv}' | openssl enc -d -aes-256-cbc -pbkdf2 -a > $HOME/.ssh/id_ed25519"], check=True)
            subprocess.run("chmod 600 ~/.ssh/id_ed25519", check=True, shell=True)
            subprocess.run("echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHx7hz8+bJjBioa3Rlvmaib8pMSd0XTmRwXwaxrT3hFL wanliz@Enzo-MacBook' > $HOME/.ssh/id_ed25519.pub", check=True, shell=True)
            subprocess.run("chmod 644 ~/.ssh/id_ed25519.pub", check=True, shell=True)
            print("~/.ssh/id_ed25519.pub \t [ ADDED ]")

        if not os.path.exists(HOME + "/.gtl_api_key"):
            cipher = "U2FsdGVkX18BU0ZpoGynLWZBV16VNV2x85CjdpJfF+JF4HhpClt/vTyr6gs6GAq0lDVWvNk7L7s7eTFcJRhEnU4IpABfxIhfktMypWw85PuJCcDXOyZm396F02KjBRwunVfNkhfuinb5y2L6YR9wYbmrGDn1+DjodSWzt1NgoWotCEyYUz0xAIstEV6lF5zedcGwSzHDdFhj3hh5YxQFANL96BFhK9aSUs4Iqs9nQIT9evjinEh5ZKNq5aJsll91czHS2oOi++7mJ9v29sU/QjaqeSWDlneZj4nPYXhZRCw="
            subprocess.run([*BASH_CMD, f"echo '{cipher}' | openssl enc -d -aes-256-cbc -pbkdf2 -a > ~/.gtl_api_key"], check=True)
            subprocess.run("chmod 500 ~/.gtl_api_key", check=True, shell=True)
            print("~/.gtl_api_key \t [ ADDED ]")


class CMD_share:
    def __str__(self):
        return "Share a Linux folder via both SMB and NFS simultaneously"
    
    def run(self):
        path = horizontal_select("Select or input folder to share", [HOME, "<input>"], 0)
        path = Path(path).resolve()
        if not (path.exists() and path.is_dir()):
            raise RuntimeError(f"Invalid path: {path}")
        self.__share_via_nfs(path)
        self.__share_via_smb(path)

    def __share_via_smb(self, path: Path):
        output = subprocess.run([*BASH_CMD, "testparm -s"], text=True, check=False, capture_output=True)
        if output.returncode != 0 and 'not found' in output.stderr:
            subprocess.run([*BASH_CMD, "sudo apt install -y samba-common-bin samba"], check=True)
            output = subprocess.run([*BASH_CMD, "testparm -s"], text=True, check=True, capture_output=True)

        for line in output.stdout.splitlines():
            if str(path) in line:
                print(f"Share {path} via SMB \t [ SHARED ]")
                return 
        
        shared_name = re.sub(r"[^A-Za-z0-9._-]","_", path.name) or "share"
        subprocess.run([*BASH_CMD, rf"""
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
        print(f"Share {path} via SMB \t [ OK ]")

    def __share_via_nfs(self, path: Path):
        output = subprocess.run([*BASH_CMD, "sudo exportfs -v"], text=True, check=False, capture_output=True)
        if output.returncode != 0 and 'not found' in output.stderr:
            subprocess.run([*BASH_CMD, "sudo apt install -y nfs-kernel-server"], check=True)
            output = subprocess.run([*BASH_CMD, "sudo exportfs -v"], text=True, check=True, capture_output=True)

        for line in output.stdout.splitlines():
            if line.strip().startswith(str(path) + " "):
                print(f"Share {path} via NFS \t [ SHARED ]")
                return
        
        subprocess.run([*BASH_CMD, rf"""
            echo '{path} *(rw,sync,insecure,no_subtree_check,no_root_squash)' | sudo tee -a /etc/exports >/dev/null 
            sudo exportfs -ra 
            sudo systemctl enable --now nfs-kernel-server
            sudo systemctl restart nfs-kernel-server
        """], check=True)
        print(f"Share {path} via NFS \t [ OK ]")


class CMD_mount:
    def __str__(self):
        return "Mount windows shared folder on Linux or the other way around"
    
    def run(self):
        if platform.system() == "Windows":
            if ctypes.windll.shell32.IsUserAnAdmin() == 0:
                cmdline = subprocess.list2cmdline([os.path.abspath(sys.argv[0])] + [arg for arg in sys.argv[1:] if arg != "--admin"])
                ctypes.windll.shell32.ShellExecuteW(None, "runas", sys.executable, cmdline, None, 1)
                sys.exit(0)
            linux_folder = horizontal_select("Linux shared folder", None, None).strip().replace("/", "\\")
            linux_folder = linux_folder.rstrip("\\")
            unc_path = linux_folder if linux_folder.startswith("\\\\") else ("\\\\" + linux_folder.lstrip("\\")) 
            drive = horizontal_select("Mount to drive", ["N", "X", "Y", "Z"], 3)
            user = horizontal_select("Target user", ["nvidia", "wanliz", "wzhu", "<input>"], 0)
            mode = horizontal_select("Target sharing protocol", ["SMB", "NFS"], 0)
            if mode == "SMB":
                subprocess.run(f'cmd /k net use {drive}: "{unc_path}" /persistent:yes {str("/user:" + user + " *") if user else ""}', check=True, shell=True)
            else:
                self.__mount_NFS_folder_on_windows(drive, unc_path, user)
        elif platform.system() == "Linux":
            windows_folder = horizontal_select("Windows shared folder", None, None).strip().replace("\\", "/")
            windows_folder = shlex.quote(windows_folder)
            mount_dir = f"/mnt/{Path(windows_folder).name}.cifs"
            user = horizontal_select("Target user", ["nvidia", "wanliz", "wzhu", "<input>"], 0)
            subprocess.run([*BASH_CMD, f"""
                if ! command -v mount.cifs >/dev/null 2>&1; then
                    sudo apt install -y cifs-utils
                fi 
                sudo mkdir -p {mount_dir} &&
                sudo mount -t cifs {windows_folder} {mount_dir} {str("-o username=" + user) if user else ""}
            """], check=True)

    def __mount_NFS_folder_on_windows(self, drive, unc_path, user):
        if os.path.exists(f"{drive}:\\"):
            raise RuntimeError(f"Drive {drive}:\\ exists")
        # Enable NFS service
        subprocess.run([
            "dism.exe", "/online", 
            "Enable-Feature", "/All", "/NoRestart", 
            "/FeatureName:ServicesForNFS-ClientOnly", 
            "/FeatureName:ClientForNFS-Infrastructure"
        ], check=True)
        # Enable Anonymous uid/gid mapping (optional)
        subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "ByPass", "-Command", rf"""
            reg add "HKLM\SOFTWARE\Microsoft\ClientForNFS\CurrentVersion\Default" /v AnonymousUid /t REG_DWORD /d 0 /f
            reg add "HKLM\SOFTWARE\Microsoft\ClientForNFS\CurrentVersion\Default" /v AnonymousGid /t REG_DWORD /d 0 /f
            nfsadmin client stop
            nfsadmin client start
        """], check=True)
        # Actual mounting
        subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "ByPass", "-Command", rf"""
            mount -o anon -p {unc_path} {drive}:
        """], check=True)


class CMD_startx:
    def __str__(self):
        return "Start a bare X server for graphics profiling"
    
    def run(self):
        headless = horizontal_select("Is this a headless system", ["yes", "no"], 1)
        withDM = horizontal_select("Start with a display manager", ["yes", "no"], 1)
        withVNC = horizontal_select("Start with a VNC server", ["yes", "no"], 1)
        unsanbag = horizontal_select("Unsanbag nvidia driver", ["yes", "no"], 0)
        lockclocks = horizontal_select("Lock GPU clocks", ["yes", "no"], 0)

        # Kill running X server
        subprocess.run([*BASH_CMD, rf"""
            if [[ ! -z $(pidof Xorg) ]]; then 
                read -p "Press [Enter] to kill running X server: "    
                sudo pkill -TERM -x Xorg
                sleep 1
            fi 
            screen -ls | awk '/Detached/ && /bareX/ {{ print $1 }}' | while IFS= read -r session; do
                screen -S "$session" -X stuff $'\r'
            done
        """], check=True)

        # Start a bare X server in GNU screen
        if headless == "yes":
            subprocess.run([*BASH_CMD, rf"""
                if [[ ! -z $(pidof Xorg) ]]; then 
                    read -p "Press [Enter] to kill running X server: "    
                    sudo pkill -TERM -x Xorg
                    sleep 1
                fi 
                screen -ls | awk '/Detached/ && /bareX/ {{ print $1 }}' | while IFS= read -r session; do
                    screen -S "$session" -X stuff $'\r'
                done
                export DISPLAY=:0 
                     
                if [[ ! -d /mnt/linuxqa/nvtest ]]; then 
                    sudo mkdir -p /mnt/linuxqa
                    sudo mount linuxqa.nvidia.com:/storage/people /mnt/linuxqa     
                fi 
                
                busID=$(nvidia-xconfig --query-gpu-info | sed -n '/PCI BusID/{{s/^[^:]*:[[:space:]]*//;p;q}}')
                sudo nvidia-xconfig -s -o /etc/X11/xorg.conf \
                    --force-generate --mode-debug --layout=Layout0 --render-accel --cool-bits=4 \
                    --mode-list=3840x2160 --depth 24 --no-ubb \
                    --x-screens-per-gpu=1 --no-separate-x-screens --busid=$busID \
                    --connected-monitor=GPU-0.DFP-0 --custom-edid=GPU-0.DFP-0:/mnt/linuxqa/nvtest/pynv_files/edids_db/ASUSPB287_DP_3840x2160x60.000_1151.bin 
                sudo screen -S bareX -dm bash -lci "__GL_SYNC_TO_VBLANK=0 X :0 vt2 -config /etc/X11/xorg.conf -logfile $HOME/X.log -logverbose 5 -ac +iglx"

                for i in $(seq 1 10); do
                    sleep 1
                    if xdpyinfo >/dev/null 2>&1; then break; fi
                    if [[ -z $(pidof Xorg) ]]; then echo "Failed to start X server"; exit 1; fi 
                done
                xhost + || true
                fbsize=$(xrandr --current 2>/dev/null | sed -n 's/^Screen .* current \([0-9]\+\) x \([0-9]\+\).*/\1x\2/p;q')
                if [[ $fbsize != "3840x2160" ]]; then 
                    grep -E "Found 0 head on board" $HOME/X.log
                    xrandr --fb 3840x2160
                fi 
                xrandr --current
                            
                {"screen -S openbox -dm openbox" if withDM == "yes" else ""}
            """], check=True)
        else:
            pass # TODO

        # Start a VNC server mirroring current display 
        if withVNC == "yes":
            subprocess.run([*BASH_CMD, rf"""
                if [[ -z $(sudo cat /etc/gdm3/custom.conf | grep -v '^#' | grep "WaylandEnable=false") ]]; then 
                    echo "{RED}Disable wayland before starting VNC server{RESET}"
                    exit 0
                fi 
                x11vnc -display :0  -rfbport 5900 -noshm -forever -noxdamage -repeat -shared -bg -o $HOME/x11vnc.log && echo "Start VNC server on :5900    [ OK ]" || cat $HOME/x11vnc.log
            """], check=True)

        # Unsandbag for much higher perf 
        if unsanbag == "yes": 
            if os.path.exists(HOME + "/sandbag-tool"):
                print("Unsangbag nvidia driver")
                subprocess.run([*BASH_CMD, f"~/sandbag-tool -unsandbag"], check=True)
            else:
                print("File doesn't exist: ~/sandbag-tool")
                print("Unsandbag \t [ FAILED ]")

        # Lock GPU clocks 
        if os.uname().machine.lower() in ("aarch64", "arm64", "arm64e"):
            if lockclocks == "yes":
                perfdebug = "/mnt/linuxqa/wanliz/iGPU_vfmax_scripts/perfdebug"
                if os.path.exists(perfdebug):
                    print("Lock GPU clocks")
                    subprocess.run([*BASH_CMD, f"sudo {perfdebug} --lock_loose  set pstateId   P0"], check=True)
                    subprocess.run([*BASH_CMD, f"sudo {perfdebug} --lock_strict set gpcclkkHz  2000000"], check=True)
                    subprocess.run([*BASH_CMD, f"sudo {perfdebug} --lock_loose  set xbarclkkHz 1800000"], check=True)
                    subprocess.run([*BASH_CMD, f"sudo {perfdebug} --force_regime  ffr"], check=True)
                else:
                    print(f"File doesn't exist: {perfdebug}")
                    print("Lock clocks \t [ FAILED ]")
        else: print("Locking GPU clocks is only required on N1x \t [ SKIPPED ]")


class CMD_nvmake:
    def __str__(self):
        return "Build nvidia driver"
    
    def run(self):
        if "P4ROOT" not in os.environ: 
            raise RuntimeError("P4ROOT is not defined")
        
        # Collect compiling arguments 
        branch = horizontal_select("[1/7] Target branch", ["r580", "bugfix_main", "<input>"], 0)
        config = horizontal_select("[2/7] Target config", ["develop", "debug", "release", "<input>"], 0)
        arch   = horizontal_select("[3/7] Target architecture", ["amd64", "aarch64", "<input>"], 0)
        module = horizontal_select("[4/7] Target module", ["drivers", "opengl", "<input>"], 0)
        regen  = horizontal_select("[5/7] Regen opengl code", ["yes", "no"], 1) if module == "opengl" else "no"
        jobs   = horizontal_select("[6/7] Number of compiling threads", [str(os.cpu_count()), "1"], 0)
        clean  = horizontal_select("[7/7] Make a clean build", ["yes", "no"], 1)

        # Clean previous builds
        if clean == "yes":
            subprocess.run([
                f"{os.environ['P4ROOT']}/tools/linux/unix-build/unix-build",
                "--unshare-namespaces", 
                "--tools",  f"{os.environ['P4ROOT']}/tools",
                "--devrel", f"{os.environ['P4ROOT']}/devrel/SDK/inc/GL",
                "nvmake", "sweep"
            ], cwd=f"{os.environ['P4ROOT']}/{branch}", check=True)

        with tempfile.TemporaryFile(mode="w+t", encoding="utf-8", delete=False) as out:
            for _branch in [self.__branch_path(b) for b in branch.split("|")]:
                for _config in config.split("|"):
                    for _arch in arch.split("|"):
                        for _module in module.split("|"):
                            try:
                                self.__unix_build_nvmake(_branch, _config, _arch, _module, regen, jobs)
                                out.write(f"{_branch},{_config},{_arch},{_module},[ OK ]\n")
                            except Exception as e:
                                out.write(f"{_branch},{_config},{_arch},{_module},[ FAILED ]\n")
            subprocess.run([*BASH_CMD, f"column -s, -o ' | ' -t {out.name}"], check=True)

    def __branch_path(self, branch):
        if branch == "r580": return "rel/gpu_drv/r580/r580_00"
        elif branch == "bugfix_main": return "dev/gpu_drv/bugfix_main"
        else: return branch 
        
    def __unix_build_nvmake(self, branch, config, arch, module, regen, jobs):
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
        

class CMD_rmmod:
    def __str__(self):
        return "Remove loaded kernel modules of nvidia driver"
    
    def run(self, retry=True):
        try:
            subprocess.run([*BASH_CMD, "sudo systemctl stop gdm gdm3 sddm lightdm xdm &>/dev/null || true"], check=True)
            subprocess.run([*BASH_CMD, "sudo fuser -k -TERM /dev/nvidia* &>/dev/null || true"], check=True)
            subprocess.run([*BASH_CMD, "sudo fuser -k -KILL /dev/nvidia* &>/dev/null || true"], check=True)
            subprocess.run([*BASH_CMD, r"""
                mods=$(lsmod | awk '/^nvidia/ {print $1}')
                if [[ -n "$mods" ]]; then 
                    echo -e "Removing modules: \n$mods"
                    sudo modprobe -r $mods 
                fi 
            """], check=True) # TODO
            subprocess.run([*BASH_CMD, "lsmod | grep -i '^nvidia' &>/dev/null || echo 'All nvidia modules are removed'"], check=True)
        except Exception:
            if retry: self.run(retry=False)
            else: raise
    
class CMD_install:
    def __str__(self):
        return "Install nvidia driver or other packages"
    
    def run(self):
        driver = horizontal_select("Driver path", ["office", "local"], 0)
        if driver == "local":
            branch, config, arch, version = self.__select_nvidia_driver("local")
            driver = os.path.join(os.environ["P4ROOT"], branch, "_out", f"Linux_{arch}_{config}", f"NVIDIA-Linux-{'x86_64' if arch == 'amd64' else arch}-{version}-internal.run")
        elif driver == "office":
            branch, config, arch, version = self.__select_nvidia_driver("office") # The entire output folder to be synced to /tmp/office/
            driver = f"/tmp/office/_out/Linux_{arch}_{config}/NVIDIA-Linux-{'x86_64' if arch == 'amd64' else arch}-{version}-internal.run"
        else: 
            raise RuntimeError("Invalid argument")
        
        if not os.path.exists(driver):
            raise RuntimeError(f"File doesn't exist: {driver}")
        
        automated = horizontal_select("Automated install", ["yes", "no"], 0)
        if automated == "yes":
            CMD_rmmod().run()
            subprocess.run([*BASH_CMD, f"sudo env IGNORE_CC_MISMATCH=1 IGNORE_MISSING_MODULE_SYMVERS=1 {driver} -s --no-kernel-module-source --skip-module-load"], check=True)
        else:
            CMD_rmmod().run()
            subprocess.run([*BASH_CMD, f"sudo env IGNORE_CC_MISMATCH=1 IGNORE_MISSING_MODULE_SYMVERS=1 {driver}"], check=True)
        subprocess.run("nvidia-smi", check=True, shell=True)

        # Copy tests-Linux-***.tar to ~
        tests = Path(driver).parent / f"tests-Linux-{'x86_64' if arch == 'amd64' else arch}.tar"
        if tests.is_file():
            subprocess.run(f"tar -xf {tests} -C {Path(driver).parent}", check=True, shell=True)
            subprocess.run(f"cp -vf {Path(driver).parent}/tests-Linux-{'x86_64' if arch == 'amd64' else arch}/sandbag-tool/sandbag-tool ~", check=True, shell=True)


    def __select_nvidia_driver(self, host):
        branch  = horizontal_select("[1/4] Target branch", ["r580", "bugfix_main"], 0)
        branch  = "rel/gpu_drv/r580/r580_00" if branch == "r580" else branch 
        branch  = "dev/gpu_drv/bugfix_main" if branch == "bugfix_main" else branch 
        config  = horizontal_select("[2/4] Target config", ["develop", "debug", "release"], 0)
        arch    = horizontal_select("[3/4] Target architecture", ["amd64", "aarch64"], 1 if os.uname().machine.lower() in ("aarch64", "arm64", "arm64e") else 0)
        version = self.__select_nvidia_driver_version(host, branch, config, arch)
        return branch, config, arch, version 
    
    def __select_nvidia_driver_version(self, host, branch, config, arch):
        if "P4ROOT" not in os.environ: 
            raise RuntimeError("P4ROOT is not defined")
        
        if host == "local":
            output_dir = os.path.join(os.environ["P4ROOT"], branch, "_out", f"Linux_{arch}_{config}")
        else:
            output_dir = f"/tmp/office/_out/Linux_{arch}_{config}"
            remote_dir = os.path.join(os.environ['P4ROOT'], branch, '_out', f'Linux_{arch}_{config}')
            subprocess.run(f"mkdir -p {output_dir}", check=True, shell=True)
            subprocess.run(f"rsync -ah --progress wanliz@{host}:{remote_dir}/ {output_dir}", check=True, shell=True)

        # Collect versions of all driver packages 
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

        # Skip selection if there is only one version available 
        if len(versions) > 1:
            selected = horizontal_select("[4/4] Target driver version", versions, 0)
        elif len(versions) == 1:
            selected = versions[0]
            print(f"[4/4] Target driver version {selected} [ONLY]")
        else: 
            raise RuntimeError("No version found")

        return versions[0] if selected == "" else selected 
    

class CMD_download:
    def __str__(self):
        return "Download packages or resources"
    
    def run(self):
        src = horizontal_select("Download", [
            "Nsight graphics",
            "Nsight systems", 
            "viewperf",
            "GravityMark",
            "3dMark - steelNomad",
        ], 0)
        if src == "Nsight graphics": self.__download_nsight_graphics()
        elif src == "Nsight systems": self.__download_nsight_systems() 
        elif src == "viewperf": self.__download_viewperf()
        elif src == "GravityMark": self.__download_gravitymark()
        elif src == "3dMark - steelNomad": self.__download_3dMark("steelNomad")

    def __download_nsight_graphics(self):
        webbrowser.open("https://ngfx/builds-nightly/Grfx")

    def __download_nsight_systems(self): 
        webbrowser.open("https://urm.nvidia.com/artifactory/swdt-nsys-generic/ctk")

    def __download_viewperf(self):
        if os.path.exists(f"/mnt/linuxqa/wanliz/viewperf2020v3/{UNAME_M}"):
            subprocess.run([*BASH_CMD, f"cp -afT /mnt/linuxqa/wanliz/viewperf2020v3/{UNAME_M} $HOME/viewperf2020v3"])
        else: raise RuntimeError(f"Folder not found: /mnt/linuxqa/wanliz/viewperf2020v3/{UNAME_M}")

    def __download_gravitymark(self):
        if os.path.exists(f"/mnt/linuxqa/wanliz/GravityMark/{UNAME_M}"):
            subprocess.run([*BASH_CMD, f"cp -afT /mnt/linuxqa/wanliz/GravityMark/{UNAME_M} $HOME/GravityMark"])
        else: raise RuntimeError(f"Folder not found: /mnt/linuxqa/wanliz/GravityMark/{UNAME_M}") 

    def __download_3dMark(self, name):
        if os.path.exists(f"/mnt/linuxqa/wanliz/3dMark_{name}/{UNAME_M}"):
            subprocess.run([*BASH_CMD, f"cp -afT /mnt/linuxqa/wanliz/3dMark_{name}/{UNAME_M} $HOME/3dMark_{name}"])
        else: raise RuntimeError(f"Folder not found: /mnt/linuxqa/wanliz/3dMark_{name}/{UNAME_M}")  


class CMD_cpu:
    def __str__(self):
        return "Configure CPU on host device"
    
    def run(self):
        cmd = horizontal_select("Action", ["max freq"], 0)
        if cmd == "max freq":
            subprocess.run([*BASH_CMD, rf"""
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
        subprocess.run([*BASH_CMD, rf"""
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
        subprocess.run([*BASH_CMD, rf"""
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


class PerfInspector_gputrace:
    def __init__(self, exe, args, workdir, env=None):
        self.pi_root = HOME + "/SinglePassCapture"
        self.exe = exe 
        self.args = args 
        self.workdir = workdir
        self.env = env 
    
    def fix(self):
        if not os.path.exists(self.pi_root):
            raise RuntimeError("PerfInspector is not installed")
        
        subprocess.run([*BASH_CMD, rf"""
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

    def capture(self, api=None, startframe=None, frames=None, name=None, upload=None, debug=None):
        if api is None: api = horizontal_select("[1/6] Capture graphics API", ["ogl", "vk"], 0)
        if startframe is None: startframe = horizontal_select("[2/6] Start capturing at frame index", ["100", "<input>"], 0)
        if frames is None: frames = horizontal_select("[3/6] Number of frames to capture", ["3", "<input>"], 0)
        if name is None: name = horizontal_select("[4/6] Output name", ["<default>", "<input>"], 0)
        if upload is None: upload = horizontal_select("[5/6] Upload output to GTL for sharing", ["yes", "no"], 1)
        if debug is None: debug = horizontal_select("[6/6] Enable pic-x debugging", ["yes", "no"], 1)
        subprocess.run([x for x in [
            "sudo", 
            f"env {' '.join(self.env)}" if self.env else "",
            self.pi_root + "/pic-x",
            "--clean=0" if debug == "yes" else "",
            f"--api={api}",
            "--check_clocks=0",
            f"--startframe={startframe}",
            f"--frames={frames}",
            "" if name == "<default>" else f"--name={name}",
            f"--exe={self.exe}",
            f"--arg={self.args}",
            f"--workdir={self.workdir}"
        ] if len(x) > 0], check=True)
        if upload == "yes":
            script = self.pi_root + f"/PerfInspector/output/{name}/upload_report.sh"
            subprocess.run(script, check=True, shell=True)

    def upload_report(self, name=None):
        if name is None:
            reports = sorted([p.name for p in Path(self.pi_root + "/PerfInspector/output").iterdir() 
                              if p.is_dir() and p.name != "perf_inspector_v2"])
            name = horizontal_select("Select a report to upload", reports, 0)
        subprocess.run([*BASH_CMD, "NVM_GTLAPI_USER=wanliz NVM_GTLAPI_TOKEN='eyJhbGciOiJIUzI1NiJ9.eyJpZCI6IjNlODVjZDU4LTM2YWUtNGZkMS1iNzZkLTZkZmZhNDg2ZjIzYSIsInNlY3JldCI6IkpuMjN0RkJuNTVMc3JFOWZIZW9tWk56a1Qvc0hpZVoxTW9LYnVTSkxXZk09In0.NzUoZbUUPQbcwFooMEhG4O0nWjYJPjBiBi78nGkhUAQ' ./upload_report.sh"], 
                       cwd=self.pi_root+f"/PerfInspector/output/{name}", 
                       check=True)
    
        
class Nsight_graphics_gputrace:
    def __init__(self, exe, args, workdir, env=None):
        self.exe = exe 
        self.args = args 
        self.workdir = workdir 
        self.env = env 
        self.__get_ngfx_path()
        self.__get_arch()
        self.__get_metricset()

    def fix(self):
        subprocess.run([*BASH_CMD, rf"""
            echo "Checking package dependencies of Nsight graphics..."
            for pkg in libxcb-dri2-0 libxcb-shape0 libxcb-xinerama0 libxcb-xfixes0 libxcb-render0 libxcb-shm0 libxcb1 libx11-xcb1 libxrender1 \
                libxkbcommon0 libxkbcommon-x11-0 libxext6 libxi6 libglib2.0-0 libglib2.0-0t64 libegl1 libopengl0 \
                libxcb-util1 libxcb-cursor0 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 libxcb-randr0 libxcb-render-util0 libxcb-xinput0; do 
                dpkg -s $pkg &>/dev/null || sudo apt install -y $pkg &>/dev/null
            done 
        """], check=True)

    def capture(self, startframe=None, frames=None, time_all_actions=None): 
        if not os.path.exists(self.ngfx):
            CMD_download().__download_nsight_graphics()

        # for N1x: --architecture="T254 GB20B" --metric-set-name="Top-Level Triage"
        if startframe is None: startframe = horizontal_select("[1/3] Start capturing at frame index", ["100", "<input>"], 0)
        if frames is None: frames = horizontal_select("[2/3] Number of frames to capture", ["3", "<input>"], 0)
        if time_all_actions is None: time_all_actions = horizontal_select("[3/3] Time all API calls separately", ["yes", "no"], 1)
        subprocess.run([*BASH_CMD, ' '.join([line for line in [
            'sudo', self.ngfx,
            '--output-dir=$HOME',
            '--platform="Linux ($(uname -m))"',
            f'--exe="{self.exe}"',
            f'--args="{self.args}"' if self.args else "",
            f'--dir="{self.workdir}"' if self.workdir else "",
            f'--env="{'; '.join(self.env)}"' if self.env else "",
            '--activity="GPU Trace Profiler"',
            f'--start-after-frames={startframe}',
            f'--limit-to-frames={frames}',
            '--auto-export',
            f'--architecture="{self.arch}"', 
            f'--metric-set-name="{self.metricset}"',
            '--multi-pass-metrics',
            '--real-time-shader-profiler',
            '--time-every-action' if time_all_actions == "yes" else ""
        ] if len(line) > 0])], check=True) 

    def __get_ngfx_path(self):
        if platform.machine() == 'aarch64':
            self.ngfx = f'{HOME}/nvidia-nomad-internal-EmbeddedLinux.l4t/host/linux-v4l_l4t-nomad-t210-a64/ngfx'
        elif os.path.isdir(f'{HOME}/nvidia-nomad-internal-Linux.linux'):
            self.ngfx = f'{HOME}/nvidia-nomad-internal-Linux.linux/host/linux-desktop-nomad-x64/ngfx'
        elif os.path.isdir(f'{HOME}/nvidia-nomad-internal-EmbeddedLinux.linux'):
            self.ngfx = f'{HOME}/nvidia-nomad-internal-EmbeddedLinux.linux/host/linux-desktop-nomad-x64/ngfx'
        else:
            self.ngfx = shutil.which('ngfx')
        self.help_all = subprocess.run([*BASH_CMD, f"{self.ngfx} --help-all"], check=False, capture_output=True, text=True).stdout

    def __get_arch(self):
        arch_list =  [l.strip() for l in re.search(r'Available architectures:\n((?:\s{2,}.+\n)+)', self.help_all).group(1).splitlines()]
        arch_list = arch_list[:next((i for i, x in enumerate(arch_list) if x == '' or x.startswith("-")), len(arch_list))] 
        self.arch = horizontal_select("Select architecture", arch_list, 0)

    def __get_metricset(self):
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
            

class CMD_viewperf:
    def __init__(self):
        self.viewperf_root = HOME + "/viewperf2020v3"

    def __str__(self):
        return "Start profiling viewperf 2020 v3"
    
    def __get_result_fps(self, viewset, subtest):
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
        except Exception as e:
            print(f"Line {e.__traceback__.tb_lineno}: {type(e).__name__}: {e}", file=sys.stderr)
            return 0
    
    def run(self):
        if not os.path.exists(self.viewperf_root):
            CMD_download().__download_viewperf()

        timestamp = perf_counter()
        subtest_nums = { "catia": 8, "creo": 13, "energy": 6, "maya": 10, "medical": 10, "snx": 10, "sw": 10 }
        self.viewset = horizontal_select("[1/3] Target viewset", ["all", "catia", "creo", "energy", "maya", "medical", "snx", "sw"], 4)
        if self.viewset == "all":
            env = "stats"
        else:
            self.subtest = horizontal_select("[2/3] Target subtest", ["all"] + [str(i) for i in range(1, subtest_nums[self.viewset] + 1)], 0)
            self.subtest = "" if self.subtest == "all" else self.subtest
            env = horizontal_select("[3/3] Launch in profiling/debug env", ["stats", "picx", "ngfx", "nsys", "gdb", "limiter"], 0)
            self.exe = self.viewperf_root + '/viewperf/bin/viewperf'
            self.arg = f"viewsets/{self.viewset}/config/{self.viewset}.xml {self.subtest} -resolution 3840x2160" 
            self.dir = self.viewperf_root
    
        if env == "stats":
            self.__run_in_stats()
        elif env == "picx":
            self.__run_in_picx()
        elif env == "ngfx":
            self.__run_in_nsight_graphics()
        elif env == "nsys":
            self.__run_in_nsight_systems()
        elif env == "gdb":
            self.__run_in_gdb()
        elif env == "limiter":
            self.__run_in_limiter()
        
        print(f"\nTime elapsed: {str(timedelta(seconds=perf_counter()-timestamp)).split('.')[0]}")
        
    def __run_in_stats(self):
        viewsets = ["catia", "creo", "energy", "maya", "medical", "snx", "sw"] if self.viewset == "all" else [self.viewset]
        subtest = None if self.viewset == "all" else self.subtest
        rounds = int(horizontal_select("Number of rounds", ["1", "3", "10", "30"], 0))
        table = ",".join(["Viewset", "Average FPS", "StdDev", "Min", "Max"])
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
                if output.returncode == 0:
                    fps = float(self.__get_result_fps(viewset, subtest)) 
                else: 
                    #print(output.stderr)
                    fps = 0
                samples.append(fps)
                print(f"{viewset}{subtest if subtest else ''} @ {i:02d} run: {fps: 3.2f} FPS")
            if rounds > 1:
                table += "\n" + ",".join([viewset, f"{mean(samples):.2f}", f"{stdev(samples):.3f}", f"{min(samples):.2f}", f"{max(samples):.2f}"])
            else:
                table += "\n" + ",".join([viewset, f"{samples[0]:.2f}", "0", f"{samples[0]:.2f}", f"{samples[0]:.2f}"])
        print("")
        output = subprocess.run([*BASH_CMD, "column -t -s ,"], input=table + "\n", text=True, check=True, capture_output=True)
        print(output.stdout if output.returncode == 0 else output.stderr)
        with open(HOME + f"/viewperf_stats_{datetime.datetime.now().strftime('%Y_%m%d_%H%M')}.txt", "w", encoding="utf-8") as file:
            file.write(output.stdout)

    def __run_in_picx(self):
        gputrace = PerfInspector_gputrace(exe=self.exe, args=self.arg, workdir=self.dir)
        gputrace.capture()

    def __run_in_nsight_graphics(self):
        gputrace = Nsight_graphics_gputrace(self.exe, self.arg, self.dir)
        gputrace.capture()

    def __run_in_nsight_systems(self):
        subprocess.run([*BASH_CMD, rf"""
            cd {self.dir}
            echo "Nsight system exe: $(which nsys)"
            sudo "$(which nsys)" profile \
                --run-as={getpass.getuser()} \
                --sample='system-wide' \
                --event-sample='system-wide' \
                --stats=true \
                --trace='cuda,nvtx,osrt,opengl' \
                --opengl-gpu-workload=true \
                --start-frame-index=100 \
                --duration-frames=60  \
                --gpu-metrics-devices=all  \
                --gpuctxsw=true \
                --output="viewperf_medical__%h__$(date '+%Y_%m%d_%H%M')" \
                --force-overwrite=true \
                {self.exe} {self.arg}
        """], cwd=HOME, check=True) 

    def __run_in_gdb(self):
        subprocess.run([*BASH_CMD, f"""
            if ! command -v cgdb >/dev/null 2>&1; then
                sudo apt install -y cgdb
            fi 
            
            gdbenv=()
            while IFS='=' read -r k v; do 
                gdbenv+=( -ex "set env $k $v" )
            done < <(env | grep -E '^(__GL_|LD_)')

            cd {self.dir}
            cgdb -- \
                -ex "set trace-commands on" \
                -ex "set pagination off" \
                -ex "set confirm off" \
                -ex "set debuginfod enabled on" \
                -ex "set breakpoint pending on" \
                "${{gdbenv[@]}}" \
                -ex "file {self.exe}" \
                -ex "set args {self.arg}" \
                -ex "set trace-commands off"
        """], check=True)

    def __run_in_limiter(self):
        choice = horizontal_select("[1/2] Emulate perf limiter of", ["CPU", "GPU"], 1)
        lowest = horizontal_select("[2/2] Emulation lower bound", ["50%", "33%", "10%"], 0)
        lowest = 5 if lowest == "50%" else (3 if lowest == "33%" else 1)
        limiter = None 
        try:
            limiter = CPU_freq_limiter() if choice == "CPU" else GPU_freq_limiter()
            for scale in [x / 10 for x in range(lowest, 11, 1)]:
                limiter.scale_max_freq(scale)
                subprocess.run([*BASH_CMD, f"{self.exe} {self.arg}"], cwd=self.dir, check=True, capture_output=True)
                print(f"{self.viewset}{self.subtest}: {self.__get_result_fps(self.viewset, self.subtest)} @ {scale:.1f}x cpu freq")
                limiter.reset()
        finally:
            if limiter is not None: limiter.reset()


class CMD_gmark:
    def __init__(self):
        self.gmark_root = HOME + "/GravityMark"
        
    def __str__(self):
        return "GravityMark benchmark for OpenGL and Vulkan on all platforms"
    
    def fix(self):
        if not os.path.exists(self.gmark_root):
            CMD_download().__download_gravitymark()

        subprocess.run([*BASH_CMD, """
            sudo apt install -y clang build-essential pkg-config libgtk2.0-dev libglib2.0-dev libpango1.0-dev libatk1.0-dev libgdk-pixbuf-2.0-dev 
        """], check=True) 
    
    def run(self):
        self.exe = f"./GravityMark.{UNAME_M2}"
        self.args = "-temporal 1  -screen 0 -fps 1 -info 1 -sensors 1 -benchmark 1 -vk -fullscreen 1 -vsync 0 -close 1"
        self.workdir = f"{HOME}/GravityMark/bin"
        subprocess.run([*BASH_CMD, f"{self.exe} {self.args}"], cwd=self.workdir, check=True) 

    def __run_in_picx(self):
        gputrace = PerfInspector_gputrace(exe=self.exe, args=self.args, workdir=self.workdir)
        gputrace.capture()


class CMD_3dmark:
    def __str__(self):
        return "3dMark benchmarks"
    
    def run(self):
        test = horizontal_select("Select 3dMark test", ["steelNomad"], 0)
        if not os.path.exists(HOME + f"/3dMark_{test}"):
            CMD_download().__download_3dMark(test)

        subprocess.run([*BASH_CMD, rf"""
            cd $HOME/3dMark_{test}/engine
            ./build/bin/dev_player --asset_root=../assets_desktop --config=configs/gt1.json
        """], check=True) 


def horizontal_select(prompt, options=None, index=None):
    global ARGPOS
    if ARGPOS > 0 and ARGPOS < len(sys.argv):
        value = sys.argv[ARGPOS]
        print(f"{BOLD}{CYAN}{prompt} : {RESET}<< {RED}{value}{RESET}")
        ARGPOS += 1
        return value 
    if options is None or index is None:
        return input(f"{BOLD}{CYAN}{prompt} : {RESET}")
    if len(options) <= index:
        return None 

    is_linux = (platform.system() == "Linux")
    stdin_fd = None 
    oldattr = None 
    try:
        if is_linux and termios and tty:
            stdin_fd = sys.stdin.fileno()
            oldattr = termios.tcgetattr(stdin_fd)
            tty.setraw(stdin_fd)

        while index >= 0 and index < len(options):
            options_str = "/".join(
                (f"{RESET}{DIM}[{option}]{RESET}{BOLD}{CYAN}" if i == index else option) 
                for i, option in enumerate(options)
            )
            sys.stdout.write("\r\033[2K" + f"{BOLD}{CYAN}{prompt} ({options_str}): {RESET}")
            sys.stdout.flush()

            ch1 = (sys.stdin.read(1) if (is_linux and termios and tty) else msvcrt.getwch())
            if ch1 in ("\r", "\n"): # Enter
                if is_linux and termios and tty:
                    termios.tcsetattr(stdin_fd, termios.TCSADRAIN, oldattr)
                sys.stdout.write("\r\n")
                sys.stdout.flush()
                return input(": ") if options[index] == "<input>" else options[index]
            
            code = None 
            if is_linux:
                if ch1 == "\x1b": # ESC or escape sequence
                    if sys.stdin.read(1) == "[":
                        tail = sys.stdin.read(1)
                        if tail == "D": code = "left"
                        elif tail == "C": code = "right"
                elif ch1 == "\x03": code = "ctrl-c"
            else:
                if ch1 in ("\x00", "\xe0"):
                    tail = msvcrt.getwch()
                    if tail == "K": code = "left"
                    elif tail == "M": code = "right"
                elif ch1 == "\x03": code = "ctrl-c"

            if code == "left": index = (len(options) if index == 0 else index) - 1
            elif code == "right": index = (-1 if index == (len(options) - 1) else index) + 1
            elif code == "ctrl-c": 
                sys.stdout.write("\r\n")
                sys.stdout.flush() 
                sys.exit(0)
    finally:
        if is_linux and termios and tty: 
            termios.tcsetattr(stdin_fd, termios.TCSADRAIN, oldattr)


def __check_env():
    global BASH_CMD
    global RESET, DIM, RED, CYAN, BOLD 
    global ERASE_LEFT, ERASE_RIGHT, ERASE_LINE
    global ARGPOS, HOME 
    global UNAME_M, UNAME_M2

    supports_ANSI = True
    if platform.system() == "Windows": 
        if ctypes.windll.shell32.IsUserAnAdmin() == 0 and "--admin" in sys.argv:
            cmdline = subprocess.list2cmdline([os.path.abspath(sys.argv[0])] + [arg for arg in sys.argv[1:] if arg != "--admin"])
            ctypes.windll.shell32.ShellExecuteW(None, "runas", sys.executable, cmdline, None, 1)
            sys.exit(0)

        BASH_CMD = ("wsl.exe", "bash", "-lc")
        ENABLE_VT = 0x0004
        kernel32 = ctypes.windll.kernel32
        stdout = msvcrt.get_osfhandle(sys.stdout.fileno())
        mode = ctypes.c_uint()
        if not kernel32.GetConsoleMode(stdout, ctypes.byref(mode)):
            supports_ANSI = False
        elif (mode.value & ENABLE_VT) == 0:
            if not kernel32.SetConsoleMode(stdout, mode.value | ENABLE_VT):
                supports_ANSI = False
    else:
        BASH_CMD = ("bash", "-lc")

    RESET = "\033[0m"  if supports_ANSI else ""
    DIM   = "\033[90m" if supports_ANSI else ""
    RED   = "\033[31m" if supports_ANSI else ""
    CYAN  = "\033[36m" if supports_ANSI else ""
    BOLD  = "\033[1m"  if supports_ANSI else ""
    ERASE_RIGHT = "\r\033[0K" if supports_ANSI else "" 
    ERASE_LEFT  = "\r\033[1K" if supports_ANSI else ""
    ERASE_LINE  = "\r\033[2K" if supports_ANSI else ""

    ARGPOS = 1
    HOME = os.path.expanduser("~") 
    HOME = HOME[:-1] if HOME.endswith("/") else HOME 
    UNAME_M, UNAME_M2 = None, None 
    if platform.machine().lower() in ["x86_64", "amd64"]: UNAME_M, UNAME_M2 = "x86_64", "x64"
    elif platform.machine().lower() in ["aarch64", "arm64"]: UNAME_M, UNAME_M2 = "aarch64", "arm64"

    os.environ.update({
        "__GL_SYNC_TO_VBLANK": "0",
        "vblank_mode": "0",
        "__GL_DEBUG_BYPASS_ASSERT": "c",
        "PIP_BREAK_SYSTEM_PACKAGES": "1"
    })
    signal.signal(signal.SIGINT, lambda s, f: sys.exit(0))


def __main_cmd_prompt():
    print(f"{RED}[use left/right arrow key to select from options]{RESET}")
    cmds = {}
    width = 0
    for name, cls in sorted(inspect.getmembers(sys.modules[__name__], inspect.isclass)):
        if cls.__module__ == __name__ and name.startswith("CMD_"):
            cmd_name = name.split("_")[1]
            cmds[cmd_name] = str(cls())
    width = max(map(len, cmds))
    for k, v in cmds.items():
        print(f"{k:>{width}} : {v}")

    cmd = horizontal_select(f"Enter the cmd to run", None, None)
    if globals().get(f"CMD_{cmd}") is None:
        raise RuntimeError(f"No command class for {cmd!r}")
    return cmd 


if __name__ == "__main__":
    try:
        __check_env() 
        cmd = __main_cmd_prompt()
        cmd = globals().get(f"CMD_{cmd}")()
        cmd.run()
    except Exception as e:
        print(f"Line {e.__traceback__.tb_lineno}: {type(e).__name__}: {e}", file=sys.stderr)
    horizontal_select("Press [Enter] to exit")
