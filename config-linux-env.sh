#!/usr/bin/env bash

if [[ -z $(which sudo) && $EUID -eq 0 ]]; then 
    apt install -y sudo 
fi 

if [[ ! -z "$USER" ]]; then 
    if ! sudo grep -qxF "$USER ALL=(ALL) NOPASSWD:ALL" /etc/sudoers; then 
        echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee -a /etc/sudoers &>/dev/null
    fi
fi 

if [[ ! -f ~/.passwd ]]; then 
    read -r -s -p "OpenSSL Password (optional): " passwd; echo
    if [[ ! -z $passwd ]]; then 
        echo -n "$passwd" > ~/.passwd    
        echo "Generated ~/.passwd"    
    fi    
fi

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
echo "Ensuring required APT packages are installed ..."
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

git_email=$(git config --global user.email 2>/dev/null || true)
if [[ -z $git_email ]]; then
    git config --global user.email "zhu.wanli@icloud.com"
fi 
git_name=$(git config --global user.name 2>/dev/null || true)
if [[ -z $git_name ]]; then
    git config --global user.name "Wanli Zhu"
fi 

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

if [[ ! -f ~/.ssh/id_ed25519 ]]; then 
    mkdir -p ~/.ssh
    cat >~/.ssh/id_ed25519 <<'EOF'
-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACB8e4c/PmyYwYqGt0Zb5mom/KTEndF05kcF8Gsa094RSwAAAJhfAHP9XwBz
/QAAAAtzc2gtZWQyNTUxOQAAACB8e4c/PmyYwYqGt0Zb5mom/KTEndF05kcF8Gsa094RSw
AAAECa55qWiuh60rKkJLljELR5X1FhzceY/beegVBrDPv6yXx7hz8+bJjBioa3Rlvmaib8
pMSd0XTmRwXwaxrT3hFLAAAAE3dhbmxpekBFbnpvLU1hY0Jvb2sBAg==
-----END OPENSSH PRIVATE KEY-----
EOF
    chmod 600 ~/.ssh/id_ed25519
    echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHx7hz8+bJjBioa3Rlvmaib8pMSd0XTmRwXwaxrT3hFL wanliz@Enzo-MacBook' > ~/.ssh/id_ed25519.pub
    chmod 644 ~/.ssh/id_ed25519.pub
    echo "Generated ~/.ssh/id_ed25519"
fi 

if [[ ! -f ~/.gtl_api_key ]]; then 
    echo 'eyJhbGciOiJIUzI1NiJ9.eyJpZCI6IjNlODVjZDU4LTM2YWUtNGZkMS1iNzZkLTZkZmZhNDg2ZjIzYSIsInNlY3JldCI6IkpuMjN0RkJuNTVMc3JFOWZIZW9tWk56a1Qvc0hpZVoxTW9LYnVTSkxXZk09In0.NzUoZbUUPQbcwFooMEhG4O0nWjYJPjBiBi78nGkhUAQ' > ~/.gtl_api_key
    chmod 500 ~/.gtl_api_key
    echo "Generated ~/.gtl_api_key"
fi 

if [[ ! -f ~/.screenrc ]]; then 
    cat >~/.screenrc <<EOF
startup_message off
termcapinfo xterm*|xterm-256color* ti@:te@
defscrollback 100000
defmousetrack off
hardstatus alwaysfirstline
hardstatus string '%{= bW} [SCREEN %H] %=%-Lw %n:%t %+Lw %=%Y-%m-%d %c '
EOF
    echo "Generated ~/.screenrc"
fi 

declare -A required_hosts=(
    ["172.16.179.143"]="office"
    ["10.31.86.235"]="horizon spark"
    ["10.176.11.106"]="horizon-proxy spark-proxy 4u2g-0110"
    ["10.178.94.106"]="gb300 galaxy"
    ["10.86.160.23"]="gb300-proxy galaxy-proxy"
)
function get_missing_hosts() {
    local host_ip host_name  
    local missing=()

    for host_ip in "${!required_hosts[@]}"; do
        local host_missing=0
        for host_name in ${required_hosts[$host_ip]}; do 
            if [[ -z $(grep $host_name /etc/hosts | grep $host_ip) ]]; then
                host_missing=1
                break
            fi
        done
        if (( host_missing )); then
            missing+=("$host_ip")
        fi 
    done
    if (( ${#missing[@]} > 0 )); then
        printf '%s\n' "${missing[@]}"
    fi 
}
echo -n "Adding known hosts into /etc/hosts ... "
mapfile -t missing_hosts < <(get_missing_hosts)
if (( ${#missing_hosts[@]} > 0 )); then 
    echo -n "Adding ${#missing_hosts[@]} missing hosts ... "
    for host_ip in "${missing_hosts[@]}"; do 
        printf '%s\t%s\n' "$host_ip" "${required_hosts[$host_ip]}" | sudo tee -a /etc/hosts >/dev/null || exit 1
    done 
    mapfile -t missing_hosts < <(get_missing_hosts)
    if (( ${#missing_hosts[@]} == 0 )); then
        echo "[OK]"
    else
        echo "[FAILED]"
    fi 
else
    echo "[SKIPPED]"
fi

declare -A required_folders=(
    ["/mnt/linuxqa"]="linuxqa.nvidia.com:/storage/people"
    ["/mnt/data"]="linuxqa.nvidia.com:/storage/data"
    ["/mnt/builds"]="linuxqa.nvidia.com:/storage3/builds"
    ["/mnt/dvsbuilds"]="linuxqa.nvidia.com:/storage5/dvsbuilds"
    ["/mnt/wanliz_sw_linux"]="office:/wanliz_sw_linux"
)
missing_folders=()
for local_folder in "${!required_folders[@]}"; do
    if ! mountpoint -q "$local_folder"; then 
        missing_folders+=("$local_folder")
    fi 
done 
echo -n "Mounting linuxqa folders ... "
if (( ${#missing_folders[@]} > 0 )); then
    failed_msg=""
    for local_folder in "${missing_folders[@]}"; do 
        remote_folder="${required_folders[$local_folder]}"
        sudo mkdir -p "$local_folder"
        sudo timeout 3 mount -t nfs "$remote_folder" "$local_folder" || { 
            failed_msg+=$'\n'"Failed to mount $remote_folder"
        }
    done 
    if [[ -z $failed_msg ]]; then 
        echo "[OK]"
    else
        echo "$failed_msg"
    fi 
else
    echo "[SKIPPED]"
fi

echo -n "Installing wanliz-utils to /usr/local/bin ..."
find /usr/local/bin -maxdepth 1 -type l -print0 | while IFS= read -r -d '' link; do 
    real_target=$(readlink -f "$link") || continue 
    if [[ $real_target == *"/wanliz-utils/"* ]]; then 
        sudo rm -f "$link" &>/dev/null 
    fi 
done 
failed_msg=""
for file in "$(realpath $(dirname $0))/apps/wanliz-utils"/*; do 
    [[ -f "$file" && -x "$file" ]] || continue 
    name=$(basename "$file")
    sudo ln -sf "$file" "/usr/local/bin/$name" &>/dev/null || {
        failed_msg+=$'\n'"Failed to create symbolic link /usr/local/bin/$name"
    }
done 
if [[ -z $failed_msg ]]; then 
    echo "[OK]"
else
    echo "$failed_msg"
fi 

echo -n "Installing inspect-gpu-perf-info ... "
$(realpath $(dirname $0))/apps/inspect-gpu-perf-info/run.sh -s -b -r &>/dev/null && {
    sudo ln -sf $(realpath $(dirname $0))/apps/inspect-gpu-perf-info/_out/Linux_$(uname -m | sed 's/x86_64/amd64/g')_release/inspect-gpu-perf-info /usr/local/bin/inspect-gpu-perf-info && echo "[OK]" || echo "[FAILED]"
} || echo "[FAILED]"


