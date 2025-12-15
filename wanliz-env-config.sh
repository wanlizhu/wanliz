#!/usr/bin/env bash

if [[ -z $(which sudo) && $EUID -eq 0 ]]; then 
    apt install -y sudo 
fi 
if [[ ! -z "$USER" && $EUID != 0 ]]; then 
    echo -n "Enabling no-password sudo ... "
    if ! sudo grep -qxF "$USER ALL=(ALL) NOPASSWD:ALL" /etc/sudoers; then 
        echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee -a /etc/sudoers &>/dev/null
        echo "[OK]"
    else
        echo "[SKIPPED]"
    fi
fi 


new_hosts_file="$HOME/wanliz/hosts"
tmp_hosts_file=$(mktemp)
if [[ ! -f /etc/hosts ]]; then 
    : >$tmp_hosts_file
else 
    awk '
    NR==FNR {
        src_line = $0
        cleaned_src_line = src_line
        sub(/#.*/, "", cleaned_src_line)
        sub(/^[[:space:]]+/, "", cleaned_src_line)
        if (cleaned_src_line != "") {
            split(cleaned_src_line, src_fields, /[[:space:]]+/)
            new_ip_list[src_fields[1]] = 1
        }
        next
    }
    {
        host_line = $0
        cleaned_host_line = host_line
        sub(/^[[:space:]]+/, "", cleaned_host_line)
        if (cleaned_host_line ~ /^#/ || cleaned_host_line == "") { print host_line; next }
        split(cleaned_host_line, host_fields, /[[:space:]]+/)
        if (!(host_fields[1] in new_ip_list)) print host_line
    }
    ' "$new_hosts_file" /etc/hosts > "$tmp_hosts_file"
fi 
if [[ -f $new_hosts_file ]]; then 
    echo -n "Checking /etc/hosts ... "
    cat $new_hosts_file >> $tmp_hosts_file
    sudo cp $tmp_hosts_file /etc/hosts
    sudo rm -f $tmp_hosts_file
    echo "[OK]"
fi 


python_version=$(python3 -c 'import sys; print(f"{sys.version_info[0]}.{sys.version_info[1]}")')
for pkg in python${python_version}-dev python${python_version}-venv \
    python3-pip python3-protobuf protobuf-compiler \
    libxcb-dri2-0 nis autofs jq rsync vim curl screen sshpass \
    lsof x11-xserver-utils x11-utils openbox obconf x11vnc \
    mesa-utils vulkan-tools xserver-xorg-core \
    samba samba-common-bin socat cmake build-essential \
    ninja-build pkg-config
do 
    if ! dpkg -s $pkg &>/dev/null; then
        if ! confirm_to_install; then  
            continue 
        fi  
        echo -n "Installing $pkg ... "
        sudo apt install -y $pkg &>/dev/null && echo "[OK]" || echo "[FAILED]"
    fi 
done 


if [[ ! -z $(which p4v) ]]; then 
    for pkg in libkf5syntaxhighlighting5 \
        libqt6webenginewidgets6 \
        qt6-webengine-dev \
        libqt6svg6 \
        libqt6multimedia6
    do 
        if ! dpkg -s $pkg &>/dev/null; then
            if ! confirm_to_install; then 
                continue 
            fi 
            echo -n "Installing $pkg ... "
            sudo apt install -y $pkg &>/dev/null && echo "[OK]" || echo "[FAILED]"
        fi 
    done 
fi 

echo -n "Installing wanliz-* scripts to /usr/local/bin ... "
find /usr/local/bin -maxdepth 1 -type l -print0 | while IFS= read -r -d '' link; do 
    if real_target=$(readlink -f "$link"); then  
        if [[ $real_target == *"/wanliz/"* ]]; then 
            sudo rm -f "$link" &>/dev/null 
        fi 
    else
        sudo rm -f "$link" &>/dev/null 
    fi 
done 
for file in $HOME/wanliz/*; do 
    [[ -f "$file" && -x "$file" ]] || continue 
    cmdname=$(basename "$file")
    cmdname="${cmdname%.sh}"
    cmdname="${cmdname%.py}"
    sudo ln -sf "$file" "/usr/local/bin/$cmdname" &>/dev/null 
done 
echo "[OK]"


if ! dpkg -s openssh-server >/dev/null 2>&1; then
    read -p "Install and set up OpenSSH server on this system? [Y/n]: " choice
    if [[ -z $choice || "$choice" == "y" ]]; then 
        echo -n "Installing openssh-server ... "
        sudo apt install -y openssh-server &>/dev/null 
        if [[ "$(cat /proc/1/comm 2>/dev/null)" == "systemd" ]] && command -v systemctl >/dev/null 2>&1; then
            sudo systemctl enable ssh &>/dev/null || true
            sudo systemctl restart ssh &>/dev/null || true
        fi
        if pgrep -x sshd >/dev/null 2>&1; then
            echo "[OK]"
        else
            echo "[FAILED]"
        fi
    fi
fi


echo -n "Updating sshd to keep client alive ... "
if ! sudo sshd -T | awk '
  $1=="clientaliveinterval" && $2=="60" {a=1}
  $1=="clientalivecountmax" && $2=="3" {b=1}
  $1=="tcpkeepalive"        && tolower($2)=="yes" {c=1}
  END { exit !(a && b && c) }'; then
    sudo ex /etc/ssh/sshd_config <<'EOF'
g/^[[:space:]]*ClientAliveInterval/d
g/^[[:space:]]*ClientAliveCountMax/d
g/^[[:space:]]*TCPKeepAlive/d
wq
EOF
    echo "ClientAliveInterval 60" | sudo tee -a  /etc/ssh/sshd_config >/dev/null 
    echo "ClientAliveCountMax 3" | sudo tee -a   /etc/ssh/sshd_config >/dev/null 
    echo "TCPKeepAlive yes" | sudo tee -a   /etc/ssh/sshd_config >/dev/null 
    sudo systemctl restart ssh
    echo "[OK]"
else
    echo "[SKIPPED]"
fi 


if [[ $USER == wanliz ]]; then 
    git_email=$(git config --global user.email 2>/dev/null || true)
    if [[ -z $git_email ]]; then
        git config --global user.email "zhu.wanli@icloud.com"
    fi 
    git_name=$(git config --global user.name 2>/dev/null || true)
    if [[ -z $git_name ]]; then
        git config --global user.name "Wanli Zhu"
    fi 
    git_editor=$(git config --global core.editor 2>/dev/null || true)
    if [[ -z $git_editor ]]; then
        if [[ -z $(which vim) ]]; then 
            sudo apt install -y vim 2>/dev/null
        fi 
        git config --global core.editor "vim"
    fi
fi 

function edit_config_file() {
    sudo python3 - "-file=$1" "-section=$2" "-name=$3" "-value=$4" <<'PY'
import pathlib
import sys


def parse_args(argv):
    result = {}
    for arg in argv:
        if arg.startswith("-") and "=" in arg:
            key, val = arg.lstrip("-").split("=", 1)
            result[key.lower()] = val
    return result


def normalize_section(raw):
    if raw is None:
        return ""
    raw = raw.strip()
    if raw.startswith("[") and raw.endswith("]"):
        raw = raw[1:-1]
    return raw.strip()


def split_kv(line):
    if not line or line.lstrip().startswith("#"):
        return None, None
    if "=" not in line:
        return None, None
    key, val = line.split("=", 1)
    key = key.strip()
    if not key:
        return None, None
    return key, val.strip()


def ensure_setting(path, section_raw, name, value):
    section = normalize_section(section_raw)
    conf = pathlib.Path(path)
    lines = conf.read_text().splitlines(keepends=True) if conf.exists() else []

    def ensure_trailing_newline():
        if lines and not lines[-1].endswith("\n"):
            lines[-1] += "\n"

    def is_section(line):
        stripped = line.strip()
        return stripped.startswith("[") and stripped.endswith("]")

    def section_name(line):
        return line.strip()[1:-1].strip()

    changed = False

    if not section:
        for idx, line in enumerate(lines):
            key, val = split_kv(line)
            if key and key.lower() == name.lower():
                if val != value:
                    lines[idx] = f"{name}={value}\n"
                    changed = True
                break
        else:
            ensure_trailing_newline()
            lines.append(f"{name}={value}\n")
            changed = True
    else:
        sec_start = None
        for idx, line in enumerate(lines):
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            if is_section(line) and section_name(line).lower() == section.lower():
                sec_start = idx
                break

        if sec_start is None:
            ensure_trailing_newline()
            lines.extend([f"[{section}]\n", f"{name}={value}\n"])
            changed = True
        else:
            sec_end = len(lines)
            for idx in range(sec_start + 1, len(lines)):
                if not lines[idx].strip() or is_section(lines[idx]):
                    sec_end = idx
                    break

            kv_idx = None
            for idx in range(sec_start + 1, sec_end):
                key, val = split_kv(lines[idx])
                if key and key.lower() == name.lower():
                    kv_idx = idx
                    if val != value:
                        lines[idx] = f"{name}={value}\n"
                        changed = True
                    break

            if kv_idx is None:
                insert_at = sec_end
                if insert_at < len(lines) and not lines[insert_at].strip():
                    insert_at += 1
                lines.insert(insert_at, f"{name}={value}\n")
                changed = True

    if changed:
        conf.write_text("".join(lines))
    return changed


def main(argv):
    opts = parse_args(argv)
    path, name, value = opts.get("file"), opts.get("name"), opts.get("value")
    if not all([path, name, value]):
        print("Missing required arguments: -file= -name= -value= (optional: -section=)", file=sys.stderr)
        return 1
    changed = ensure_setting(path, opts.get("section"), name, value)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
PY
}

if [[ $USER == wanliz && -d /mnt/c/Users/ ]]; then 
    echo -n "Checking appendWindowsPath=false in /etc/wsl.conf ... "
    if sudo grep -Eq '^[[:space:]]*appendWindowsPath[[:space:]]*=[[:space:]]*false[[:space:]]*$' /etc/wsl.conf 2>/dev/null; then
        echo "[SKIPPED]"
    else
        if edit_config_file "/etc/wsl.conf" "[interop]" "appendWindowsPath" "false"; then
            echo "[OK]"
        else
            echo "[FAILED]"
        fi
    fi
fi 

if [[ $USER == wanliz && ! -f ~/.vimrc ]]; then 
    cat <<'EOF' > ~/.vimrc
set expandtab
set tabstop=4
set shiftwidth=4
set softtabstop=4
EOF
fi 

if [[ $USER == wanliz && ! -f ~/.screenrc ]]; then
    cat <<'EOF' > ~/.screenrc
caption always "%{= bw}%{+b} %t (%n) | %H | %Y-%m-%d %c | load %l"
hardstatus on
hardstatus alwayslastline "%{= kW}%-w%{= kG}%n*%t%{-}%+w %=%{= ky}%H %{= kw}%Y-%m-%d %c %{= kc}load %l"
EOF
fi 


echo -n "Mounting /mnt/linuxqa ... "
if [[ ! -d /mnt/linuxqa ]]; then 
    sudo mkdir -p /mnt/linuxqa 
fi 
if mountpoint -q /mnt/linuxqa; then 
    echo "[SKIPPED]"
else
    timeout 5s sudo mount -t nfs linuxqa.nvidia.com:/storage/people /mnt/linuxqa && echo "[OK]" || {
        echo "[FAILED] - rerun for debug info"
        timeout 1s sudo mount -vvv -t nfs linuxqa.nvidia.com:/storage/people /mnt/linuxqa 
        dmesg | tail -10
    }
fi 


if [[ -d /mnt/linuxqa/wanliz ]]; then 
    if [[ -z $(which p4) && -f /mnt/linuxqa/wanliz/p4.$(uname -m) ]]; then 
        sudo cp -f /mnt/linuxqa/wanliz/p4.$(uname -m) /usr/local/bin/p4 
    fi 
    if [[ ! -d $HOME/p4v && -d /mnt/linuxqa/wanliz/p4v.$(uname -m) ]]; then 
        cp -rf /mnt/linuxqa/wanliz/p4v.$(uname -m)/  $HOME/p4v/ 
    fi 
fi 

echo "All done!"
