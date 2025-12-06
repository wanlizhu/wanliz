#!/usr/bin/env bash

export P4PORT="p4proxy-sc.nvidia.com:2006"
export P4USER="wanliz"
export P4CLIENT="wanliz_sw_linux"
export P4ROOT="/wanliz_sw_linux"

changelist=$1
if [[ -z $changelist ]]; then 
    echo "Missing cmdline arguments:"
    echo "    \$1 - changelist to checkout"
    exit 1
fi 

p4 describe -s $changelist
echo 
echo "Affected files (diff) ..."
echo 
p4 opened -c $changelist | awk '{print $1}' | p4 -x - diff -du 
