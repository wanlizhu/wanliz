#!/usr/bin/env bash

cat /wanliz_sw_windows_wsl2/workingbranch/drivers/common/inc/nvUnixVersion.h | grep '#define' | grep NV_VERSION_STRING | awk -F'"' '{print $2}'