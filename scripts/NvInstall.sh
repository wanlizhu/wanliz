#!/bin/bash

host=$([[ -d /wanliz_sw_linux ]] && echo localhost || echo "wanliz@office")
root="${P4ROOT:-/wanliz_sw_linux}"
branch=rel/gpu_drv/r580/r580_00
subdir=
config=develop 
module=drivers
while [[ $# -gt 0 ]]; do 
    case $1 in 
        office) host="wanliz@office" ;;
        /*) root=$1 ;;
        bfm)  branch=dev/gpu_drv/bugfix_main ;;
        r580) branch=rel/gpu_drv/r580/r580_00 ;;
        debug|release|develop) config=$1 ;;
        opengl) module=opengl; subdir="drivers/OpenGL" ;;
    esac
    shift 
done 

case $module in 
    drivers) driver="$root/$branch/$subdir/_out/Linux_$(uname -m | sed 's/^x86_64$/amd64/')_$config/NVIDIA-Linux-$(uname -m)-*.run" ;;
    opengl)  driver="$root/$branch/$subdir/_out/Linux_$(uname -m | sed 's/^x86_64$/amd64/')_$config/libnvidia-glcore.so" ;;
    *) echo "Error: unknown module: \"$module\""; exit 1 ;;
esac 
if [[ "$host" != localhost ]]; then 
    #sudo rm -rf /tmp/drivers  
    mkdir -p /tmp/drivers 
    source ~/wanliz/scripts/NvConfig.sh && NoPasswd-SSH "$host" 
    echo "Downloading from $host:$driver"
    rsync -ah --progress "$host:$driver" /tmp/drivers  
    if [[ $driver == *".run" ]]; then 
        rsync -ah --progress "$host:$(dirname $driver)/tests-Linux-$(uname -m).tar" /tmp/drivers  
    fi 
    driver="/tmp/drivers/$(basename $driver)"
fi 

if [[ $(ls $driver | wc -l) -gt 1 ]]; then 
    ls $(dirname $driver)/NVIDIA-Linux-$(uname -m)-*.run 2>/dev/null | awk -F/ '{print $NF}' | sort -V | sed -E 's/([0-9]+\.[0-9]+)/\x1b[31m\1\x1b[0m/'
    read -p "Install version: " version
    driver="$(dirname $driver)/NVIDIA-Linux-$(uname -m)-$version-internal.run"
else
    driver="$(realpath $driver)"
fi 

if [[ ! -f $driver ]]; then 
    echo "Error: file not found: $driver"
    exit 1
fi 

read -p "Press [Enter] to install $driver:"

if [[ $driver == *".run" ]]; then 
    echo "Kill all graphics apps and install $driver"
    read -p "Press [Enter] to continue: "
    source ~/wanliz/scripts/NvConfig.sh && Remove-Nvidia-Kernel-Module 
    sleep 3
    
    sudo env IGNORE_CC_MISMATCH=1 IGNORE_MISSING_MODULE_SYMVERS=1 $driver -s --no-kernel-module-source --skip-module-load || { 
        cat /var/log/nvidia-installer.log
        echo "Aborting..."
        exit 1
    }

    if [[ -f $(dirname $driver)/tests-Linux-$(uname -m).tar ]]; then 
        tar -xf $(dirname $driver)/tests-Linux-$(uname -m).tar -C /tmp 
        sudo cp -vf /tmp/tests-Linux-$(uname -m)/sandbag-tool/sandbag-tool $HOME/sandbag-tool  
    fi 
elif [[ $driver == *".so" ]]; then 
    version=$(ls /usr/lib/*-linux-gnu/$(basename $driver).*  | awk -F '.so.' '{print $2}' | head -1)
    sudo cp -vf --remove-destination $driver /usr/lib/$(uname -m)-linux-gnu/$(basename $driver).$version 
else
    echo "Error: unknown driver format: \"$driver\""
    exit 1
fi 