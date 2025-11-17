#!/usr/bin/env bash

apt_has_updated=0
update_success_stamp=/var/lib/apt/periodic/update-success-stamp
if [[ -f $update_success_stamp ]]; then 
    now=$(date +%s)
    stamp=$(stat -c %Y "$update_success_stamp")
    if (( now - stamp < 1440 * 60 )); then
        apt_has_updated=1
    fi
fi  

if (( ! apt_has_updated )); then 
    if [[ "$EUID" -eq 0 ]]; then 
        apt update -y || true 
    else
        sudo apt update -y || true 
    fi 
fi 

if [[ -z $(which sudo) && $EUID -eq 0 ]]; then 
    apt install -y sudo 
    apt_has_updated=1
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
)
echo "Ensuring required APT packages are installed ..."
if [[ -z $apt_has_updated ]]; then
    sudo apt update &>/dev/null || true 
fi
for cmd in "${{!dependencies[@]}}"; do
    if ! command -v "$cmd" &>/dev/null; then
        pkg="${{dependencies[$cmd]}}"
        echo -n "Installing $pkg ... "
        sudo apt install -y "$pkg" >/dev/null 2>/tmp/err && echo "[OK]" || {{ 
            echo "[FAILED]"
            cat /tmp/err 
        }}
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
echo -n "Checking /etc/hosts of known hosts ... "
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
    echo "[OK]"
fi

