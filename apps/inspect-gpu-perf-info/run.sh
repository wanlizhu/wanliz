#!/usr/bin/env bash

if [[ $1 == -s ]]; then 
    sudo apt install -y \
        mesa-vulkan-drivers \
        vulkan-tools \
        vulkan-validationlayers \
        libvulkan-dev
fi 

workspace=$(dirname $0)
outdir=$workspace/_out/Linux_$(uname -m | sed 's/x86_64/amd64/g')_debug
mkdir -p $outdir 
cd $outdir || exit 1
cmake ../.. || exit 1
make || exit 1
./inspect-gpu-perf-info
