#!/usr/bin/env bash

export P4PORT="p4proxy-sc.nvidia.com:2006"
export P4USER="wanliz"
export P4CLIENT="wanliz_sw_linux"
export P4ROOT="/wanliz_sw_linux"

time p4 sync  
resolve_files=$(p4 resolve -n $P4ROOT/... 2>/dev/null)
if [[ ! -z $resolve_files ]]; then 
    echo "Need resolve, trying auto-merge"
    p4 resolve -am $P4ROOT/... 
    conflict_files=$(p4 resolve $P4ROOT/... 2>/dev/null)
    if [[ ! -z $conflict_files ]]; then 
        echo "$(echo $conflict_files | wc -l) conflict files remain [Manual Merge]"
        echo $conflict_files
    else
        echo "No manual resolved needed"
    fi
else
    echo "No resolves needed"
fi 