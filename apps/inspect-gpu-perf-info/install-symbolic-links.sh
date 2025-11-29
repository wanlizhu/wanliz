#!/usr/bin/env bash

outdir=$(realpath $(dirname $0))/_out/Linux_$(uname -m | sed 's/x86_64/amd64/g')_release
mkdir -p $outdir 
cd $outdir  
cmake ../.. || exit 1
sudo cmake --build . || exit 1
sudo ln -sfv $outdir/inspect-gpu-perf-info /usr/local/bin/inspect-gpu-perf-info || exit 1
sudo ln -sfv $outdir/VkLayer_inspect_gpu_perf_info.json /usr/share/vulkan/explicit_layer.d/VkLayer_inspect_gpu_perf_info.json || exit 1
sudo ln -sfv $(realpath $(dirname $0))/merge-gpu-pages.sh /usr/local/bin/merge-gpu-pages.sh || exit 1

if [[ -z $(which inspect-gpu-page-tables) ]]; then 
    echo "Action required to install inspect-gpu-page-tables"
    exit 1
fi 

# Install helper to communicate with kernel on aarch64
if [[ $(uname -m) == "aarch64" && ! -e /dev/nvidia-soc-iommu-inspect ]]; then 
    if [[ ! -d $P4ROOT/pvt/aritger/apps/inspect-gpu-page-tables/nvidia-soc-iommu-inspect ]]; then 
        echo "Missing folder: \$P4ROOT/pvt/aritger/apps/inspect-gpu-page-tables/nvidia-soc-iommu-inspect"
        exit 1
    fi 
    cd $P4ROOT/pvt/aritger/apps/inspect-gpu-page-tables/nvidia-soc-iommu-inspect 
    make || exit 1
    sudo insmod ./nvidia-soc-iommu-inspect.ko || exit 1
    sudo ./create-dev-node.sh || exit 1
fi 