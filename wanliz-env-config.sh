#!/usr/bin/env bash

if [[ -z $(which sudo) && $EUID -eq 0 ]]; then 
    apt install -y sudo 
fi 

if [[ ! -z "$USER" ]]; then 
    if ! sudo grep -qxF "$USER ALL=(ALL) NOPASSWD:ALL" /etc/sudoers; then 
        echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee -a /etc/sudoers &>/dev/null
    fi
fi 


echo -n "Updating /etc/hosts ... "
new_hosts_file="$(dirname $0)/hosts"
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
cat $new_hosts_file >> $tmp_hosts_file
sudo cp $tmp_hosts_file /etc/hosts
sudo rm -f $tmp_hosts_file
echo "[OK]"


declare -A dependencies=(
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
    [socat]=socat
    [cmake]=cmake
    [g++]=build-essential
    [ninja]=ninja-build
    [pkg-config]=pkg-config
)
echo "Checking required packages ..."
for cmd in "${!dependencies[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
        pkg="${dependencies[$cmd]}"
        echo -n "Installing $pkg ... "
        sudo apt install -y "$pkg" >/dev/null 2>/tmp/err && echo "[OK]" || {
            echo "[FAILED]"
            cat /tmp/err 
        }
    fi
done
python_version=$(python3 -c 'import sys; print(f"{sys.version_info[0]}.{sys.version_info[1]}")')
for pkg in python${python_version}-dev \
    python3-pip python3-protobuf protobuf-compiler 
do 
    if ! dpkg -s $pkg &>/dev/null; then
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
            echo -n "Installing $pkg ... "
            sudo apt install -y $pkg &>/dev/null && echo "[OK]" || echo "[FAILED]"
        fi 
    done 
fi 


echo -n "Installing wanliz-utils to /usr/local/bin ... "
find /usr/local/bin -maxdepth 1 -type l -print0 | while IFS= read -r -d '' link; do 
    real_target=$(readlink -f "$link") || continue 
    if [[ $real_target == *"/wanliz/"* ]]; then 
        sudo rm -f "$link" &>/dev/null 
    fi 
done 
for file in "$(realpath $(dirname $0))/*"; do 
    [[ -f "$file" && -x "$file" ]] || continue 
    cmdname=$(basename "$file")
    cmdname="${cmdname%.sh}"
    sudo ln -sf "$file" "/usr/local/bin/$cmdname" &>/dev/null 
done 
echo "[OK]"


declare -A required_folders=(
    ["/mnt/linuxqa"]="linuxqa.nvidia.com:/storage/people"
    ["/mnt/data"]="linuxqa.nvidia.com:/storage/data"
    ["/mnt/builds"]="linuxqa.nvidia.com:/storage3/builds"
    ["/mnt/dvsbuilds"]="linuxqa.nvidia.com:/storage5/dvsbuilds"
)
missing_required_folders=()
for local_folder in "${!required_folders[@]}"; do
    if ! mountpoint -q "$local_folder"; then 
        missing_required_folders+=("$local_folder")
    fi 
done 


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


echo -n "Mounting /mnt/linuxqa ... "
if [[ ! -d /mnt/linuxqa ]]; then 
    sudo mkdir -p /mnt/linuxqa 
fi 
if mountpoint -q /mnt/linuxqa; then 
    echo "[SKIPPED]"
else
    sudo mount -t nfs linuxqa.nvidia.com:/storage/people /mnt/linuxqa && echo "[OK]" || echo "[FAILED] (exit=$?)"
fi 


if [[ -d /mnt/linuxqa/wanliz ]]; then 
    if [[ -z $(which p4) && -f /mnt/linuxqa/wanliz/p4.$(uname -m) ]]; then 
        sudo cp -f /mnt/linuxqa/wanliz/p4.$(uname -m)/ /usr/local/bin/p4v/
    fi 
    if [[ ! -d $HOME/p4v && -d /mnt/linuxqa/wanliz/p4v.$(uname -m) ]]; then 
        cp -rf /mnt/linuxqa/wanliz/p4v.$(uname -m)/. $HOME/p4v/
    fi 
fi 


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
