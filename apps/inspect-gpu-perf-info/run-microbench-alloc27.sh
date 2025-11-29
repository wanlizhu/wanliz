#!/usr/bin/env bash

nvperf_vulkan_path=/mnt/linuxqa/wanliz/nvperf_vulkan.$(uname -m)
if [[ ! -e "$nvperf_vulkan_path" ]]; then 
    echo "Action required to set up nvperf_vulkan_path in $0"
    exit 1
fi 

DEBUG_MEM_ALLOC=1 $(realpath $(dirname $0))/run-generic-app.sh $nvperf_vulkan_path -nullDisplay alloc:27 
