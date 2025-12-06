#!/usr/bin/env bash

export P4PORT="p4proxy-sc.nvidia.com:2006"
export P4USER="wanliz"
export P4CLIENT="wanliz_sw_linux"
export P4ROOT="/wanliz_sw_linux"

p4 changes -s pending -u $P4USER -c $P4CLIENT | while read -r line; do 
    changelist=$(echo "$line" | awk '{print $2}')
    if [[ -z $(p4 opened -c $changelist 2>/dev/null) ]]; then
        echo "$line #shelved"
    else
        echo "$line #opened"
    fi
done 