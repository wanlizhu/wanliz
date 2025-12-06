#!/usr/bin/env bash

export P4PORT="p4proxy-sc.nvidia.com:2006"
export P4USER="wanliz"
export P4CLIENT="wanliz_sw_linux"
export P4ROOT="/wanliz_sw_linux"

if [[ -f "$1" ]]; then 
    wanliz-nvrmmod
    chmod +x "$1" &>/dev/null || true 
    failed=
    if [[ $2 == "-i" ]]; then 
        sudo env IGNORE_CC_MISMATCH=1 IGNORE_MISSING_MODULE_SYMVERS=1 "$1" || failed=1
    else
        sudo env IGNORE_CC_MISMATCH=1 IGNORE_MISSING_MODULE_SYMVERS=1 "$1" -s --no-kernel-module-source --skip-module-load || failed=1
    fi 
    if [[ $failed -eq 1 ]]; then 
        cat '/var/log/nvidia-installer.log'
    else 
        echo "$1" >~/.driver 
        echo "Generated ~/.driver"
    fi 
    if [[ -f /tmp/nvrmmod.restore ]]; then 
        eval "$(cat /tmp/nvrmmod.restore)"
        sudo rm -f /tmp/nvrmmod.restore
    fi 
elif [[ $1 == "redo" ]]; then 
    if [[ ! -f $(cat ~/.driver) ]]; then
        echo "Invalid path in ~/.driver"
        exit 1
    fi 
    wanliz-nvinstall $(cat ~/.driver $@)
elif [[ ! -z $1 ]]; then  
    if sudo test ! -d /root/nvt; then 
        sudo /mnt/linuxqa/nvt.sh sync
    fi 
    sudo env NVTEST_INSTALLER_REUSE_INSTALL=False /mnt/linuxqa/nvt.sh drivers "$@" 2>/tmp/std2 | tee /tmp/std1 
    cat /tmp/std2
    driver=$(cat /tmp/std2 | grep 'NVTEST_DRIVER=' | awk '{print $2}' | awk -F'=' '{print $2}')
    if [[ ! -z $driver ]]; then 
        if [[ $driver == "http"* ]]; then 
            mkdir -p $HOME/drivers
            local_driver=$HOME/drivers/$(basename "$driver")
            wget --no-check-certificate -O $local_driver $driver || exit 1
            echo "$local_driver" > ~/.driver 
            echo "Generated ~/.driver"
        elif [[ -f $driver ]]; then 
            echo "$driver" > ~/.driver 
            echo "Generated ~/.driver"
        fi 
    fi 
else 
    find /wanliz_sw_linux/dev /wanliz_sw_linux/rel -type d -name '_out' -exec find '{}' -type f -name 'NVIDIA-Linux*.run' \; 2>/dev/null
fi 