#!/usr/bin/env bash

if [[ ! -e /dev/nvidia-soc-iommu-inspect && $(uname -m) == "aarch64" ]]; then 
    if [[ ! -d /mnt/wanliz_sw_linux ]]; then 
        echo "Mount /mnt/wanliz_sw_linux first"
        exit 1   
    fi 

    rsync -ha --info=progress2 /mnt/wanliz_sw_linux/pvt/aritger/apps/inspect-gpu-page-tables/nvidia-soc-iommu-inspect /tmp  || exit 1
    cd /tmp/nvidia-soc-iommu-inspect  
    make || exit 1
    sudo insmod ./nvidia-soc-iommu-inspect.ko 
    sudo ./create-dev-node.sh
fi 

if [[ -z $(which inspect-gpu-page-tables) ]]; then 
    cp -vf /mnt/linuxqa/wanliz/inspect-gpu-page-tables.$(uname -m) /usr/local/bin/inspect-gpu-page-tables
fi 

sudo /usr/local/bin/inspect-gpu-page-tables 