#!/usr/bin/env bash
trap 'exit 130' INT

export P4PORT="p4proxy-sc.nvidia.com:2006"
export P4USER="wanliz"
export P4CLIENT="wanliz_sw_windows_wsl2"
export P4ROOT="/$P4CLIENT"

if [[ -f "$1" ]]; then 
    wanliz-rmmod-nvidia
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
    if [[ -f /tmp/rmmod.restore ]]; then 
        eval "$(cat /tmp/rmmod.restore)"
        sudo rm -f /tmp/rmmod.restore
    fi 
elif [[ $1 == "redo" ]]; then 
    if [[ ! -f $(cat ~/.driver) ]]; then
        echo "Invalid path in ~/.driver"
        exit 1
    fi 
    wanliz-install-driver $(cat ~/.driver $@)
elif [[ $1 == *@* ]]; then 
    LOGIN_INFO="$1"
    TARGET=
    CONFIG=
    ARCH=$(uname -m | sed 's/x86_64/amd64/g')
    VERSION=
    RESTORE=
    shift 
    while [[ ! -z $1 ]]; do 
        case $1 in 
            opengl|drivers) TARGET=$1 ;;
            debug|release|develop) CONFIG=$1 ;;
            amd64|x64|x86_64) [[ $(uname -m) != "x86_64"  ]] && { echo "Invalid arch $1"; exit 1; } ;;
            aarch64|arm64)    [[ $(uname -m) != "aarch64" ]] && { echo "Invalid arch $1"; exit 1; } ;;
            [0-9]*) VERSION=$1 ;;
            -r|--restore) RESTORE=1 ;;
        esac
        shift 
    done 
    [[ -z $TARGET  ]] && { echo  "TARGET is not specified"; exit 1; }
    [[ -z $CONFIG  ]] && { echo  "CONFIG is not specified"; exit 1; }
    [[ -z $VERSION ]] && { echo "VERSION is not specified"; exit 1; }
    if [[ $TARGET == drivers ]]; then 
        rsync -ah --info=progress2 $LOGIN_INFO:/wanliz_sw_windows_wsl2/workingbranch/_out/Linux_${ARCH}_${CONFIG}/NVIDIA-Linux-$(uname -m)-${VERSION}-internal.run $HOME/NVIDIA-Linux-$(uname -m)-${CONFIG}-${VERSION}-internal.run || exit 1
        rsync -ah --info=progress2 $LOGIN_INFO:/wanliz_sw_windows_wsl2/workingbranch/_out/Linux_${ARCH}_${CONFIG}/tests-Linux-$(uname -m).tar $HOME/NVIDIA-Linux-$(uname -m)-${CONFIG}-${VERSION}-tests.tar
        wanliz-install-driver $HOME/NVIDIA-Linux-$(uname -m)-${CONFIG}-${VERSION}-internal.run
    elif [[ $TARGET == opengl ]]; then 
        if [[ $RESTORE == 1 ]]; then 
            if [[ -f $HOME/libnvidia-glcore.so.$VERSION.backup ]]; then 
                sudo cp -vf --remove-destination $HOME/libnvidia-glcore.so.$VERSION.backup /usr/lib/$(uname -m)-linux-gnu/libnvidia-glcore.so.$VERSION
                sudo cp -vf --remove-destination $HOME/libnvidia-eglcore.so.$VERSION.backup /usr/lib/$(uname -m)-linux-gnu/libnvidia-eglcore.so.$VERSION
                sudo cp -vf --remove-destination $HOME/libnvidia-glsi.so.$VERSION.backup /usr/lib/$(uname -m)-linux-gnu/libnvidia-glsi.so.$VERSION
                sudo cp -vf --remove-destination $HOME/libnvidia-tls.so.$VERSION.backup /usr/lib/$(uname -m)-linux-gnu/libnvidia-tls.so.$VERSION
                sudo cp -vf --remove-destination $HOME/libGLX_nvidia.so.$VERSION.backup /usr/lib/$(uname -m)-linux-gnu/libGLX_nvidia.so.$VERSION
                
                sudo rm -f $HOME/libnvidia-glcore.so.$VERSION.backup
                sudo rm -f $HOME/libnvidia-eglcore.so.$VERSION.backup
                sudo rm -f $HOME/libnvidia-glsi.so.$VERSION.backup
                sudo rm -f $HOME/libnvidia-tls.so.$VERSION.backup
                sudo rm -f $HOME/libGLX_nvidia.so.$VERSION.backup
                echo "Restored original OpenGL drivers"
            else
                echo "$HOME/libnvidia-glcore.so.$VERSION.backup doesn't exist"
            fi 
        else 
            rsync -ah --progress $LOGIN_INFO:/wanliz_sw_windows_wsl2/workingbranch/drivers/OpenGL/_out/Linux_${ARCH}_${CONFIG}/libnvidia-glcore.so $HOME/libnvidia-glcore.so.$VERSION
            rsync -ah --progress $LOGIN_INFO:/wanliz_sw_windows_wsl2/workingbranch/drivers/OpenGL/win/egl/build/_out/Linux_${ARCH}_${CONFIG}/libnvidia-eglcore.so $HOME/libnvidia-eglcore.so.$VERSION 
            #rsync -ah --progress $LOGIN_INFO:/wanliz_sw_windows_wsl2/workingbranch/drivers/OpenGL/win/egl/glsi/_out/Linux_${ARCH}_${CONFIG}/libnvidia-glsi.so $HOME/libnvidia-glsi.so.$VERSION 
            rsync -ah --progress $LOGIN_INFO:/wanliz_sw_windows_wsl2/workingbranch/drivers/OpenGL/win/unix/tls/Linux-elf/_out/Linux_${ARCH}_${CONFIG}/libnvidia-tls.so $HOME/libnvidia-tls.so.$VERSION 
            rsync -ah --progress $LOGIN_INFO:/wanliz_sw_windows_wsl2/workingbranch/drivers/OpenGL/win/glx/lib/_out/Linux_${ARCH}_${CONFIG}/libGLX_nvidia.so $HOME/libGLX_nvidia.so.$VERSION  
            
            if [[ ! -e /usr/lib/$(uname -m)-linux-gnu/libnvidia-glcore.so.$VERSION ]]; then 
                echo "Incompatible version $VERSION"
                exit 1
            fi 

            read -p "Press [Enter] to continue: "
            
            if [[ -f $HOME/libnvidia-glcore.so.$VERSION.backup ]]; then 
                echo "Reuse existing backups"
            else
                sudo cp /usr/lib/$(uname -m)-linux-gnu/libnvidia-glcore.so.$VERSION $HOME/libnvidia-glcore.so.$VERSION.backup
                sudo cp /usr/lib/$(uname -m)-linux-gnu/libnvidia-eglcore.so.$VERSION $HOME/libnvidia-eglcore.so.$VERSION.backup
                sudo cp /usr/lib/$(uname -m)-linux-gnu/libnvidia-glsi.so.$VERSION $HOME/libnvidia-glsi.so.$VERSION.backup
                sudo cp /usr/lib/$(uname -m)-linux-gnu/libnvidia-tls.so.$VERSION $HOME/libnvidia-tls.so.$VERSION.backup
                sudo cp /usr/lib/$(uname -m)-linux-gnu/libGLX_nvidia.so.$VERSION $HOME/libGLX_nvidia.so.$VERSION.backup
            fi 

            sudo cp -vf --remove-destination $HOME/libnvidia-glcore.so.$VERSION /usr/lib/$(uname -m)-linux-gnu/libnvidia-glcore.so.$VERSION
            sudo cp -vf --remove-destination $HOME/libnvidia-eglcore.so.$VERSION /usr/lib/$(uname -m)-linux-gnu/libnvidia-eglcore.so.$VERSION
            sudo cp -vf --remove-destination $HOME/libnvidia-glsi.so.$VERSION /usr/lib/$(uname -m)-linux-gnu/libnvidia-glsi.so.$VERSION
            sudo cp -vf --remove-destination $HOME/libnvidia-tls.so.$VERSION /usr/lib/$(uname -m)-linux-gnu/libnvidia-tls.so.$VERSION
            sudo cp -vf --remove-destination $HOME/libGLX_nvidia.so.$VERSION /usr/lib/$(uname -m)-linux-gnu/libGLX_nvidia.so.$VERSION
        fi 
    fi 
else 
    if sudo test ! -d /root/nvt; then 
        sudo /mnt/linuxqa/nvt.sh sync
    fi 
    sudo env NVTEST_INSTALLER_REUSE_INSTALL=False /mnt/linuxqa/nvt.sh drivers "$@" 2>/tmp/std2 | tee /tmp/std1 
    cat /tmp/std2
    driver_src=$(cat /tmp/std2 | grep 'NVTEST_DRIVER=' | awk '{print $2}' | awk -F'=' '{print $2}')
    driver_dst=$HOME/$(basename "$driver_src")
    if [[ ! -z $driver_src ]]; then 
        sudo cp -vf /root/nvt/driver/$(basename "$driver_src") $driver_dst 
        sudo cp -vf /root/nvt/driver/tests-Linux-$(uname -m).tar $(dirname $driver_dst)
        echo "$driver_dst" > ~/.driver 
        echo "Generated ~/.driver"
    fi 
fi 