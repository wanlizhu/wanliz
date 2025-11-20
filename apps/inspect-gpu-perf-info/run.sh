#!/usr/bin/env bash

build_only=
build_config=debug
for arg in "$@"; do 
    if [[ $arg == -s ]]; then 
        sudo apt install -y \
            build-essential clang \
            mesa-vulkan-drivers \
            vulkan-tools \
            vulkan-validationlayers \
            libvulkan-dev
    elif [[ $arg == -b ]]; then 
        build_only=1
    elif [[ $arg == -r ]]; then 
        build_config=release
    fi 
done 

workspace=$(realpath $(dirname $0))
outdir=$workspace/_out/Linux_$(uname -m | sed 's/x86_64/amd64/g')_${build_config}
mkdir -p $outdir 
cd $outdir || exit 1
cmake ../.. || exit 1
make || exit 1

if [[ -z $build_only ]]; then 
    ./inspect-gpu-perf-info
fi 
