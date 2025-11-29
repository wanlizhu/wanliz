#!/usr/bin/env bash

$(realpath $(dirname $0))/install-symbolic-links.sh || exit 1

nvperf_vulkan_path=/mnt/linuxqa/wanliz/nvperf_vulkan.$(uname -m)
if [[ ! -e "$nvperf_vulkan_path" ]]; then 
    echo "Action required to set up nvperf_vulkan_path in $0"
    exit 1
fi 

sudo env DEBUG_MEM_ALLOC=1 inspect-gpu-perf-info $nvperf_vulkan_path -nullDisplay alloc:27 2>/tmp/igpi.txt
