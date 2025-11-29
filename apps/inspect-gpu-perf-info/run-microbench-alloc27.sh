#!/usr/bin/env bash

$(realpath $(dirname $0))/install-symbolic-links.sh || exit 1

nvperf_vulkan_path=/mnt/linuxqa/wanliz/nvperf_vulkan.$(uname -m)
if [[ ! -e "$nvperf_vulkan_path" ]]; then 
    echo "Action required to set up nvperf_vulkan_path in $0"
    exit 1
fi 

sudo env DEBUG_MEM_ALLOC=1 inspect-gpu-perf-info $nvperf_vulkan_path -nullDisplay alloc:27 2> /tmp/igpi.txt

if [[ -f /tmp/igpi.txt ]]; then 
    vkalloc_logs=
    vkalloc_logs_begin=
    while IFS= read line; do 
        case "$line" in 
            "vkAllocateMemory BEGIN"*)
                echo "$line"
                vkalloc_logs=""
                vkalloc_logs_begin=1
            ;;
            "vkAllocateMemory ENDED"*)
                echo "$line"
                vkalloc_logs_begin=0
                printf "%s\n" "$vkalloc_logs" > /tmp/vkalloc_logs
                $(realpath $(dirname $0))/process-vidheap.py /tmp/vkalloc_logs
            ;;
            *)
                if [[ "$vkalloc_logs_begin" = 1 ]]; then
                    vkalloc_logs="$vkalloc_logs$line"$'\n'
                else
                    echo "$line"
                fi 
            ;;
        esac
    done < /tmp/igpi.txt > /tmp/igpi_processed.txt
    sudo mv -f /tmp/igpi_processed.txt $HOME/igpi_mb_alloc27.txt
    echo "Logs dumped to $HOME/igpi_mb_alloc27.txt"
fi 
