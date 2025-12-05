#!/usr/bin/env bash

cd $HOME/wanliz/apps/inspect-gpu-perf-info
mkdir -p _out/Linux_debug
cd _out/Linux_debug  
cmake ../.. || exit 1
sudo cmake --build . --config debug || exit 1
sudo ln -sfv $(pwd)/inspect-gpu-perf-info /usr/local/bin/inspect-gpu-perf-info || exit 1
sudo ln -sfv $(pwd)/VK_LAYER_igpi_helper.json /usr/share/vulkan/explicit_layer.d/VK_LAYER_igpi_helper.json || exit 1

function check_p4_env() {
    export P4PORT="p4proxy-sc.nvidia.com:2006"
    export P4USER="wanliz"
    
    if ! command -v p4 &>/dev/null; then 
        sudo cp -vf /mnt/linuxqa/wanliz/p4.$(uname -m) /usr/local/bin/p4 || exit 1
    fi 

    if ! p4 login -s &>/dev/null; then 
        p4 login 
    fi 
}

if [[ -z $(which inspect-gpu-page-tables) ]]; then 
    if [[ -f /mnt/linuxqa/wanliz/inspect-gpu-page-tables.$(uname -m) ]]; then 
        sudo cp -vf /mnt/linuxqa/wanliz/inspect-gpu-page-tables.$(uname -m) /usr/local/bin/inspect-gpu-page-tables
    else
        echo "Action required to install inspect-gpu-page-tables"
        exit 
    fi 
fi 

# Install helper to communicate with kernel on aarch64
if [[ $(uname -m) == "aarch64" && ! -e /dev/nvidia-soc-iommu-inspect ]]; then 
    if [[ ! -d /tmp/nvidia-soc-iommu-inspect ]]; then 
        check_p4_env -login
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
