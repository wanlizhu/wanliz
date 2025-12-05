#!/usr/bin/env bash

function check_p4_env() {
    export P4PORT="p4proxy-sc.nvidia.com:2006"
    export P4USER="wanliz"
    
    if ! command -v p4 &>/dev/null; then 
        if [[ ! -f /etc/apt/sources.list.d/perforce.list ]]; then 
                sudo mkdir -p /usr/share/keyrings
                wget -qO- https://package.perforce.com/perforce.pubkey | gpg --dearmor | sudo tee /usr/share/keyrings/perforce-archive-keyring.gpg >/dev/null
                . /etc/os-release 
                echo "deb [signed-by=/usr/share/keyrings/perforce-archive-keyring.gpg] http://package.perforce.com/apt/ubuntu ${UBUNTU_CODENAME} release" | sudo tee /etc/apt/sources.list.d/perforce.list >/dev/null
        fi 
        sudo apt update
        sudo apt install -y helix-cli 
    fi 

    if ! p4 login -s &>/dev/null; then 
        p4 login 
    fi 
}

if [[ -z $(which inspect-gpu-page-tables) ]]; then 
    echo "Action required to install inspect-gpu-page-tables"
    exit 
fi 

# Install helper to communicate with kernel on aarch64
if [[ $(uname -m) == "aarch64" && ! -e /dev/nvidia-soc-iommu-inspect ]]; then 
    if [[ ! -d /tmp/nvidia-soc-iommu-inspect ]]; then 
        check_p4_env
        p4 files "//sw/pvt/aritger/apps/inspect-gpu-page-tables/nvidia-soc-iommu-inspect/..." | awk '{print $1}' | while read depot_file; do 
            local_file=${depot_file#//sw/pvt/aritger/apps/inspect-gpu-page-tables/nvidia-soc-iommu-inspect/}
            local_file=${local_file%%#*}
            local_file="/tmp/nvidia-soc-iommu-inspect/$local_file"
            mkdir -p $(dirname $local_file)
            p4 print -q -o $local_file $depot_file
        done 
    fi 

    cd /tmp/nvidia-soc-iommu-inspect || exit 1
    make || exit 1
    sudo insmod ./nvidia-soc-iommu-inspect.ko || exit 1
    sudo ./create-dev-node.sh || exit 1
fi 

