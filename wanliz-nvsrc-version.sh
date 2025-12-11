#!/usr/bin/env bash

if [[ -d /wanliz_sw_linux ]]; then 
    export NV_SOURCE="/wanliz_sw_linux/dev/gpu_drv/bugfix_main"
elif [[ -d /wanliz_sw_windows_wsl2 ]]; then 
    export NV_SOURCE="/wanliz_sw_windows_wsl2/workingbranch"
fi 

cat $NV_SOURCE/drivers/common/inc/nvUnixVersion.h | grep '#define' | grep NV_VERSION_STRING | awk -F'"' '{print $2}'