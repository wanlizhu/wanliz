#!/bin/bash

export PATH="$PATH:$HOME/Wanli-Tools:/mnt/linuxqa/wanliz/Wanli-Tools"
export __GL_SYNC_TO_VBLANK=0
export vblank_mode=0
export __GL_DEBUG_BYPASS_ASSERT=c 
export PIP_BREAK_SYSTEM_PACKAGES=1
export NVM_GTLAPI_USER=wanliz
export NVM_GTLAPI_TOKEN='eyJhbGciOiJIUzI1NiJ9.eyJpZCI6IjNlODVjZDU4LTM2YWUtNGZkMS1iNzZkLTZkZmZhNDg2ZjIzYSIsInNlY3JldCI6IkpuMjN0RkJuNTVMc3JFOWZIZW9tWk56a1Qvc0hpZVoxTW9LYnVTSkxXZk09In0.NzUoZbUUPQbcwFooMEhG4O0nWjYJPjBiBi78nGkhUAQ'
export QT_QPA_PLATFORM_PLUGIN_PATH="/usr/lib/$(uname -m)-linux-gnu/qt5/plugins/platforms" # For qapitrace
[[ -z $SSL_CERT_DIR ]] && export SSL_CERT_DIR=/etc/ssl/certs
[[ -z $DISPLAY ]] && export DISPLAY=:0

# Export Perforce variables 
export P4PORT=p4proxy-sc.nvidia.com:2006
export P4USER=wanliz
export P4CLIENT=wanliz_sw_linux
export P4ROOT=/wanliz_sw_linux
export P4IGNORE=$HOME/.p4ignore
[[ ! -f ~/.p4ignore ]] && echo "_out
    .git
    .vscode
    .cursorignore
    .clangd
    .p4config
    .p4ignore
    compile-commands.json
    *.code-workspace" | sed 's/^[[:space:]]*//' > ~/.p4ignore

# Mount /mnt/linuxqa
ping -c1 -W1 linuxqa.nvidia.com &>/dev/null \
    && ! mountpoint -q /mnt/linuxqa &>/dev/null \
    && sudo mkdir -p /mnt/linuxqa &>/dev/null \
    && sudo mount linuxqa.nvidia.com:/storage/people /mnt/linuxqa &>/dev/null

# Enable no-password sudo
[[ $EUID -ne 0 ]] \
    && ! sudo grep -qxF "$USER ALL=(ALL) NOPASSWD:ALL" /etc/sudoers \
    && echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee -a /etc/sudoers &>/dev/null

# Add known host names to /etc/hosts
declare -A _address_=(
    [office]="172.16.179.143"
    [proxy]="10.176.11.106"
    [horizon5]="172.16.178.123"
    [horizon6]="172.16.177.182"
    [horizon7]="172.16.177.216"
    [n1x6]="10.31.40.241"
)
for _host_ in "${!_address_[@]}"; do 
    _ip_=${_address_[$_host_]}
    if sudo grep -Eq "${_host_}" /etc/hosts; then
        sudo sed -i "/$_host_/d" /etc/hosts
    fi
    printf '%s %s\n' "$_ip_" "$_host_" | sudo tee -a /etc/hosts &>/dev/null
done 
unset _address_ _host_ _ip_

# Ensure env loader defined in ~/.bashrc
grep -qF 'function Load-Wanli-Tools' "$HOME/.bashrc" || cat >>"$HOME/.bashrc" <<'EOF'
function Load-Wanli-Tools {
    if [[ -f ~/Wanli-Tools/NvConfig.sh ]]; then 
        source ~/Wanli-Tools/NvConfig.sh
    elif [[ -f /mnt/linuxqa/wanliz/Wanli-Tools/NvConfig.sh ]]; then 
        source /mnt/linuxqa/wanliz/Wanli-Tools/NvConfig.sh
    else
        echo "Folder ~/Wanli-Tools doesn't exist"
    fi 
}
export -f Load-Wanli-Tools
if [[ $USER == wanliz ]]; then
    Load-Wanli-Tools
fi
EOF
source $HOME/.bashrc

# <<<<<<<<<<<<<<<<<<<< Begin: helper functions
function Sync-Wanli-Tools {
    if [[ -d ~/Wanli-Tools ]]; then 
        pushd ~/Wanli-Tools >/dev/null 
        if [[ -n $(git status --porcelain=v1 2>/dev/null) ]]; then
            git add . && git commit -m "$(date)"
            git pull && git push
        else
            git pull 
        fi 
        popd >/dev/null
    fi 

    if [[ -d /mnt/linuxqa/wanliz/Wanli-Tools ]]; then 
        pushd /mnt/linuxqa/wanliz/Wanli-Tools >/dev/null 
        echo -e "\nUpdating /mnt/linuxqa/wanliz/Wanli-Tools"
        git -c safe.directory='*' pull
        popd >/dev/null 
    fi 
}

function Add-SSH-Key {
    if [[ -f ~/.ssh/id_ed25519 ]]; then 
        read -p "Press [Enter] to override ~/.ssh/id_ed25519: "
        sudo rm -rf ~/.ssh/id_ed25519 ~/.ssh/id_ed25519.pub 
    fi 
    echo "Generating ~/.ssh/id_ed25519"
    echo 'U2FsdGVkX1/M3Vl9RSvWt6Nkq+VfxD/N9C4jr96qvbXsbPfxWmVSfIMGg80m6g946QCdnxBxrNRs0i9M0mijcmJzCCSgjRRgE5sd2I9Buo1Xn6D0p8LWOpBu8ITqMv0rNutj31DKnF5kWv52E1K4MJdW035RHoZVCEefGXC46NxMo88qzerpdShuzLG8e66IId0kEBMRtWucvhGatebqKFppGJtZDKW/W1KteoXC3kcAnry90H70x2fBhtWnnK5QWFZCuoC16z+RQxp8p1apGHbXRx8JStX/om4xZuhl9pSPY47nYoCAOzTfgYLFanrdK10Jp/huf40Z0WkNYBEOH4fSTD7oikLugaP8pcY7/iO0vD7GN4RFwcB413noWEW389smYdU+yZsM6VNntXsWPWBSRTPaIEjaJ0vtq/4pIGaEn61Tt8ZMGe8kKFYVAPYTZg/0bai1ghdA9CHwO9+XKwf0aL2WalWd8Amb6FFQh+TlkqML/guFILv8J/zov70Jxz/v9mReZXSpDGnLKBpc1K1466FnlLJ89buyx/dh/VXJb+15RLQYUkSZou0S2zxo' | openssl enc -d -aes-256-cbc -pbkdf2 -a > ~/.ssh/id_ed25519
    chmod 600 ~/.ssh/id_ed25519
    echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHx7hz8+bJjBioa3Rlvmaib8pMSd0XTmRwXwaxrT3hFL wanliz@Enzo-MacBook' > ~/.ssh/id_ed25519.pub 
    chmod 644 ~/.ssh/id_ed25519.pub
}

function Add-GTL-API-Key {
    echo "Generating ~/.gtl_api_key"
    echo 'U2FsdGVkX18BU0ZpoGynLWZBV16VNV2x85CjdpJfF+JF4HhpClt/vTyr6gs6GAq0lDVWvNk7L7s7eTFcJRhEnU4IpABfxIhfktMypWw85PuJCcDXOyZm396F02KjBRwunVfNkhfuinb5y2L6YR9wYbmrGDn1+DjodSWzt1NgoWotCEyYUz0xAIstEV6lF5zedcGwSzHDdFhj3hh5YxQFANL96BFhK9aSUs4Iqs9nQIT9evjinEh5ZKNq5aJsll91czHS2oOi++7mJ9v29sU/QjaqeSWDlneZj4nPYXhZRCw=' | openssl enc -d -aes-256-cbc -pbkdf2 -a > ~/.gtl_api_key 
    chmod 500 ~/.gtl_api_key 
}

function NoPasswd-SSH {
    if ! ssh -v \
      -o BatchMode=yes \
      -o PreferredAuthentications=publickey \
      -o NumberOfPasswordPrompts=0 \
      -o StrictHostKeyChecking=accept-new \
      -o IdentitiesOnly=yes \
      -o ConnectTimeout=2 \
      "$1" true &>/dev/null; then
        if [[ ! -f ~/.ssh/id_rsa ]]; then 
            ssh-keygen -t rsa -b 4096 -o -a 100 -N '' -f $HOME/.ssh/id_rsa
        fi 
        ssh-copy-id -i "$HOME/.ssh/id_rsa.pub" "$1"
        if [[ ! -f ~/.ssh/id_ed25519 ]]; then 
            Add-SSH-Key || return 1
        fi 
        ssh-copy-id -i "$HOME/.ssh/id_ed25519.pub" "$1"
    fi
}

function Mount-Windows-Folder {
    [[ -z $(which mount.cifs) ]] && sudo apt install -y cifs-utils
    read -r -p "Windows Shared Folder: " FolderURL
    URL=$(echo "$FolderURL" | sed 's|\\|/|g')
    sudo mkdir -p /mnt/$(basename $FolderURL).cifs
    sudo mount -t cifs $FolderURL /mnt/$(basename $FolderURL).cifs -o username=wanliz && echo "Mounted at /mnt/$(basename $FolderURL).cifs" || echo "FAILED"
}

function Copy-to-Windows-Desktop {
    if [[ ! -z "$1" ]]; then 
        read -p "Windows Host IP: " -e -i "$(cat $HOME/.windows-host-ip 2>/dev/null)" host
        echo "$host" > $HOME/.windows-host-ip
        [[ -z $(which sshpass) ]] && sudo apt install -y sshpass
        if [[ ! -f /tmp/.windows-host-passwd ]]; then  
            echo "$(echo 'U2FsdGVkX1+UnE9oAYZ8DjyHzGqQ3wxZbhrJanHFw9u7ypNWEkG2dOJQShrj5dlT' | openssl enc -d -aes-256-cbc -pbkdf2 -a)" > /tmp/.windows-host-passwd
        fi 
        sshpass -p "$(cat /tmp/.windows-host-passwd)" scp -r -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "$@" WanliZhu@$host:'C:\Users\WanliZhu\Desktop\'
    fi 
}

function Remove-Nvidia-Kernel-Module {
    sudo fuser -v /dev/nvidia* 2>/dev/null | grep -v 'COMMAND' | awk '{print $3}' | sort | uniq | tee > /tmp/nvidia
    for nvpid in $(cat /tmp/nvidia); do 
        echo -n "Killing $nvpid "
        sudo kill -9 $nvpid && echo " ... OK" || echo "-> Failed"
        sleep 1
    done

    while :; do
        removed=0
        for m in $(lsmod | awk '/^nvidia/ {print $1}'); do
            if [ ! -d "/sys/module/$m/holders" ] || [ -z "$(ls -A /sys/module/$m/holders 2>/dev/null)" ]; then
                sudo rmmod -f "$m" && removed=1
                echo "Remove kernel module $m ... OK"
            fi
        done
        [ "$removed" -eq 0 ] && break
    done
}
# <<<<<<<<<<<<<<<<<<<< End: helper functions