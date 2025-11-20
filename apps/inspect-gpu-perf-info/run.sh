#!/usr/bin/env bash

install=
build_config=debug
target=
for arg in "$@"; do 
    if [[ $arg == -setup ]]; then 
        sudo apt install -y \
            build-essential clang \
            mesa-vulkan-drivers \
            vulkan-tools \
            vulkan-validationlayers \
            libvulkan-dev
    elif [[ $arg == -install ]]; then 
        install=1
    elif [[ $arg == -release ]]; then 
        build_config=release
    elif [[ $arg == -target=* ]]; then 
        target="${arg#-target=}"
    fi 
done 

workspace=$(realpath $(dirname $0))
outdir=$workspace/_out/Linux_$(uname -m | sed 's/x86_64/amd64/g')_${build_config}
mkdir -p $outdir 
cd $outdir || exit 1
cmake ../.. || exit 1
make || exit 1

if [[ $install -eq 1 ]]; then 
    make install 
else
    ./inspect-gpu-perf-info $target 
fi 
