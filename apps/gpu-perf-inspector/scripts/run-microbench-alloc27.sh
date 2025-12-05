#!/usr/bin/env bash

$(realpath $(dirname $0))/install.sh || exit 1

if [[ -z $(which nvperf_vulkan) ]]; then 
    nvperf_vulkan_path=/mnt/linuxqa/wanliz/nvperf_vulkan.$(uname -m)
    if [[ ! -e "$nvperf_vulkan_path" ]]; then 
        echo "Action required to set up nvperf_vulkan_path in $0" >&2
        exit 1
    fi 
else
    nvperf_vulkan_path=$(which nvperf_vulkan)
fi 

sudo env ENABLE_RMLOG=1 gpu-perf-inspector $nvperf_vulkan_path -nullDisplay alloc:27 2>/tmp/rmlogs.txt

if [[ -f /tmp/rmlogs.txt ]]; then 
    vkalloc_logs=
    vkalloc_logs_begin=
    while IFS= read line; do 
        case "$line" in 
            "vkAllocateMemory begin"*)
                echo "$line"
                vkalloc_logs_begin=1
                vkalloc_logs=""
            ;;
            "vkAllocateMemory end"*)
                printf "%s\n" "$vkalloc_logs" >/tmp/vkalloc_logs
                $(realpath $(dirname $0))/process_vidheap.py /tmp/vkalloc_logs
                vkalloc_logs_begin=0
                echo "$line"
            ;;
            *)
                # Ignore logs outside of BEGIN and ENDED markers
                if [[ "$vkalloc_logs_begin" = 1 ]]; then
                    vkalloc_logs="$vkalloc_logs$line"$'\n'
                fi 
            ;;
        esac
    done < /tmp/rmlogs.txt > /tmp/rmlogs_cooked.txt
    sudo mv -f /tmp/rmlogs_cooked.txt $HOME/rmlogs_alloc27.txt

    if ! grep -q '[^[:space:]]' $HOME/rmlogs_alloc27.txt; then
        echo "No logs found"
        cat /tmp/rmlogs.txt
    else 
        echo "Logs dumped to $HOME/rmlogs_alloc27.txt"
        cat $HOME/rmlogs_alloc27.txt
    fi 
fi 
