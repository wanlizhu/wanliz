#!/usr/bin/env bash

mkdir -p $(dirname $0)/../_out/Linux_debug
outdir=$(realpath $(dirname $0)/../_out/Linux_debug)
cd $outdir || exit 1
cmake ../.. || exit 1
sudo cmake --build . --config debug || exit 1
sudo ln -sfv $outdir/inspect-gpu-perf-info /usr/local/bin/inspect-gpu-perf-info || exit 1
sudo ln -sfv $outdir/VK_LAYER_igpi_helper.json /usr/share/vulkan/explicit_layer.d/VK_LAYER_igpi_helper.json || exit 1
sudo ln -sfv $(realpath $outdir/../..)/scripts/merge-gpu-pages.sh /usr/local/bin/merge-gpu-pages.sh || exit 1

if [[ -z $(which inspect-gpu-page-tables) ]]; then 
    if [[ -f /mnt/linuxqa/wanliz/inspect-gpu-page-tables.$(uname -m) ]]; then 
        sudo cp -f /mnt/linuxqa/wanliz/inspect-gpu-page-tables.$(uname -m) /usr/local/bin/inspect-gpu-page-tables &>/dev/null 
    fi 
    if [[ -z $(which inspect-gpu-page-tables) ]]; then 
        echo "Action required to install inspect-gpu-page-tables" >&2
    fi 
fi 

# Install helper to communicate with kernel on aarch64
if [[ $(uname -m) == "aarch64" && ! -e /dev/nvidia-soc-iommu-inspect ]]; then 
    if [[ -d $P4ROOT/pvt/aritger/apps/inspect-gpu-page-tables/nvidia-soc-iommu-inspect ]]; then 
        cd $P4ROOT/pvt/aritger/apps/inspect-gpu-page-tables/nvidia-soc-iommu-inspect 
        make || exit 1
        sudo insmod ./nvidia-soc-iommu-inspect.ko || exit 1
        sudo ./create-dev-node.sh || exit 1
    else 
        echo "Missing folder: \$P4ROOT/pvt/aritger/apps/inspect-gpu-page-tables/nvidia-soc-iommu-inspect" >&2
    fi 
fi 

if [[ -f /mnt/linuxqa/wanliz/nvperf_vulkan.$(uname -m) ]]; then 
    sudo cp -f /mnt/linuxqa/wanliz/nvperf_vulkan.$(uname -m) $HOME/nvperf_vulkan
fi 