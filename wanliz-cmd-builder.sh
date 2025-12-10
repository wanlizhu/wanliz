#!/usr/bin/env bash

if [[ $1 == p4env ]]; then 
    echo 'export P4PORT="p4proxy-sc.nvidia.com:2006"
export P4USER="wanliz"
export P4CLIENT="wanliz_sw_linux"
export P4ROOT="/wanliz_sw_linux"'
fi 