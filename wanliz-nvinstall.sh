#!/usr/bin/env bash

export P4PORT="p4proxy-sc.nvidia.com:2006"
export P4USER="wanliz"
export P4CLIENT="wanliz_sw_windows_wsl2"
export P4ROOT="/$P4CLIENT"

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
elif [[ $1 == *@* ]]; then 
    LOGIN_INFO="$1"
    TARGET=
    CONFIG=
    ARCH=$(uname -m | sed 's/x86_64/amd64/g')
    VERSION=
    shift 
    while [[ ! -z $1 ]]; do 
        case $1 in 
            opengl|drivers) TARGET=$1 ;;
            debug|release|develop) CONFIG=$1 ;;
            amd64|x64|x86_64) [[ $(uname -m) != "x86_64"  ]] && { echo "Invalid arch $1"; exit 1; } ;;
            aarch64|arm64)    [[ $(uname -m) != "aarch64" ]] && { echo "Invalid arch $1"; exit 1; } ;;
            [0-9]*) VERSION=$1 ;;
        esac
        shift 
    done 
    [[ -z $TARGET  ]] && { echo  "TARGET is not specified"; exit 1; }
    [[ -z $CONFIG  ]] && { echo  "CONFIG is not specified"; exit 1; }
    [[ -z $VERSION ]] && { echo "VERSION is not specified"; exit 1; }
    if [[ $TARGET == drivers ]]; then 
    
        rsync -ah --info=progress2 $LOGIN_INFO:/wanliz_sw_windows_wsl2/workingbranch/_out/Linux_${ARCH}_${CONFIG}/NVIDIA-Linux-${ARCH}-${VERSION}-internal.run $HOME/NVIDIA-Linux-${ARCH}-${CONFIG}-${VERSION}-internal.run || exit 1
        rsync -ah --info=progress2 $LOGIN_INFO:/wanliz_sw_windows_wsl2/workingbranch/_out/Linux_${ARCH}_${CONFIG}/tests-Linux-aarch64.tar $HOME/NVIDIA-Linux-${ARCH}-${CONFIG}-${VERSION}-tests.tar
        wanliz-nvinstall $HOME/NVIDIA-Linux-${ARCH}-${CONFIG}-${VERSION}-internal.run
    elif [[ $TARGET == opengl ]]; then 
        rsync -ah --info=progress2 $LOGIN_INFO:/wanliz_sw_windows_wsl2/workingbranch/drivers/OpenGL/_out/Linux_amd64_develop/libnvidia-glcore.so $HOME/libnvidia-glcore.so.$VERSION 
        if [[ ! -e /usr/lib/$(uname -m)-linux-gnu/libnvidia-glcore.so.$VERSION ]]; then 
            echo "Incompatible version $VERSION"
            exit 1
        fi 
        sudo cp -vf --remove-destination $HOME/libnvidia-glcore.so.$VERSION /usr/lib/$(uname -m)-linux-gnu/libnvidia-glcore.so.$VERSION
    fi 
elif [[ $1 == nvt ]]; then  
    shift 
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
fi 