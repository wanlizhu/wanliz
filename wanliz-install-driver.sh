#!/usr/bin/env bash
trap 'exit 130' INT

export P4PORT="p4proxy-sc.nvidia.com:2006"
export P4USER="wanliz"
export P4CLIENT="wanliz_sw_windows_wsl2"
export P4ROOT="/$P4CLIENT"

rm -f $HOME/.driver

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
        echo "$1" >$HOME/.driver 
        echo "Generated $HOME/.driver"
    fi 
    if [[ -f /tmp/rmmod.restore ]]; then 
        eval "$(cat /tmp/rmmod.restore)"
        sudo rm -f /tmp/rmmod.restore
    fi 
elif [[ $1 == "redo" ]]; then 
    if [[ ! -f $(cat $HOME/.driver) ]]; then
        echo "Invalid path in $HOME/.driver"
        exit 1
    fi 
    wanliz-install-driver $(cat $HOME/.driver $@)
elif [[ $1 == *@* ]]; then 
    LOGIN_INFO="$1"
    TARGET=
    CONFIG=
    ARCH=$(uname -m | sed 's/x86_64/amd64/g')
    VERSION=
    RESTORE=
    NOSYSDIR=
    shift 
    while [[ ! -z $1 ]]; do 
        case $1 in 
            opengl|drivers) TARGET=$1 ;;
            debug|release|develop) CONFIG=$1 ;;
            amd64|x64|x86_64) [[ $(uname -m) != "x86_64"  ]] && { echo "Invalid arch $1"; exit 1; } ;;
            aarch64|arm64)    [[ $(uname -m) != "aarch64" ]] && { echo "Invalid arch $1"; exit 1; } ;;
            [0-9]*) VERSION=$1 ;;
            -r|--restore) RESTORE=1 ;;
            -n|--nosysdir) NOSYSDIR=1 ;;
        esac
        shift 
    done  
    [[ -z $TARGET  ]] && { echo  "TARGET is not specified"; exit 1; }
    [[ -z $CONFIG  ]] && { echo  "CONFIG is not specified"; exit 1; }
    [[ -z $VERSION ]] && { echo "VERSION is not specified"; exit 1; }
    if [[ $TARGET == drivers ]]; then 
        rsync -ah --info=progress2 $LOGIN_INFO:/wanliz_sw_windows_wsl2/workingbranch/_out/Linux_${ARCH}_${CONFIG}/NVIDIA-Linux-$(uname -m)-${VERSION}-internal.run $HOME/NVIDIA-Linux-$(uname -m)-${CONFIG}-${VERSION}-internal.run || exit 1
        rsync -ah --info=progress2 $LOGIN_INFO:/wanliz_sw_windows_wsl2/workingbranch/_out/Linux_${ARCH}_${CONFIG}/tests-Linux-$(uname -m).tar $HOME/NVIDIA-Linux-$(uname -m)-${CONFIG}-${VERSION}-tests.tar
        
        if [[ $NOSYSDIR == 1 ]]; then 
            pushd $HOME >/dev/null
                sudo mv -f NVIDIA-Linux-$(uname -m)-${VERSION}-internal /tmp/
                chmod +x $HOME/NVIDIA-Linux-$(uname -m)-${CONFIG}-${VERSION}-internal.run
                $HOME/NVIDIA-Linux-$(uname -m)-${CONFIG}-${VERSION}-internal.run -x 
                mv NVIDIA-Linux-$(uname -m)-${VERSION}-internal NVIDIA-Linux-$(uname -m)-${CONFIG}-${VERSION}-internal
                pushd NVIDIA-Linux-$(uname -m)-${CONFIG}-${VERSION}-internal >/dev/null || exit 1
                    for dso_file in *.so.$VERSION; do 
                        [[ $dso_file == "*.so.$VERSION" ]] && continue 
                        [[ $dso_file =~ ^(.+\.so)\..+ ]] || continue
                        basename=${BASH_REMATCH[1]}
                        ln -sfn $dso_file $basename
                        for i in 0 1 2 3 4; do
                            ln -sfn $dso_file $basename.$i
                        done 
                    done 
                popd >/dev/null 
            popd >/dev/null 
            echo 
            echo "LD_LIBRARY_PATH=$HOME/NVIDIA-Linux-$(uname -m)-${CONFIG}-${VERSION}-internal${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH} ..."
        else 
            echo "$HOME/NVIDIA-Linux-$(uname -m)-${CONFIG}-${VERSION}-internal.run"
            read -p "Press [Enter] to continue: "
            wanliz-install-driver $HOME/NVIDIA-Linux-$(uname -m)-${CONFIG}-${VERSION}-internal.run
        fi 
    elif [[ $TARGET == opengl ]]; then 
        if [[ $RESTORE == 1 ]]; then 
            if [[ $NOSYSDIR == 1 ]]; then 
                echo "--restore option has been ignored"
                exit 0
            fi  
            if [[ -f $HOME/libnvidia-glcore.so.$VERSION.backup ]]; then 
                sudo cp -vf --remove-destination $HOME/libnvidia-glcore.so.$VERSION.backup /usr/lib/$(uname -m)-linux-gnu/libnvidia-glcore.so.$VERSION
                sudo cp -vf --remove-destination $HOME/libnvidia-eglcore.so.$VERSION.backup /usr/lib/$(uname -m)-linux-gnu/libnvidia-eglcore.so.$VERSION
                sudo cp -vf --remove-destination $HOME/libnvidia-glsi.so.$VERSION.backup /usr/lib/$(uname -m)-linux-gnu/libnvidia-glsi.so.$VERSION
                sudo cp -vf --remove-destination $HOME/libnvidia-tls.so.$VERSION.backup /usr/lib/$(uname -m)-linux-gnu/libnvidia-tls.so.$VERSION
                sudo cp -vf --remove-destination $HOME/libGLX_nvidia.so.$VERSION.backup /usr/lib/$(uname -m)-linux-gnu/libGLX_nvidia.so.$VERSION
                sudo cp -vf --remove-destination $HOME/libEGL_nvidia.so.$VERSION.backup /usr/lib/$(uname -m)-linux-gnu/libEGL_nvidia.so.$VERSION
                
                sudo rm -f $HOME/libnvidia-glcore.so.$VERSION.backup
                sudo rm -f $HOME/libnvidia-eglcore.so.$VERSION.backup
                sudo rm -f $HOME/libnvidia-glsi.so.$VERSION.backup
                sudo rm -f $HOME/libnvidia-tls.so.$VERSION.backup
                sudo rm -f $HOME/libGLX_nvidia.so.$VERSION.backup
                sudo rm -f $HOME/libEGL_nvidia.so.$VERSION.backup
                echo "Restored original OpenGL drivers"
            else
                echo "$HOME/libnvidia-glcore.so.$VERSION.backup doesn't exist"
            fi 
        else 
            if [[ $NOSYSDIR == 1 ]]; then
                RSYNC_DST=$HOME/NVIDIA-Linux-$(uname -m)-${CONFIG}-${VERSION}-opengl
                rm -rf $RSYNC_DST
                mkdir -p $RSYNC_DST
            else
                RSYNC_DST=$HOME 
            fi 
            rsync -ah --progress $LOGIN_INFO:/wanliz_sw_windows_wsl2/workingbranch/drivers/OpenGL/_out/Linux_${ARCH}_${CONFIG}/libnvidia-glcore.so $RSYNC_DST/libnvidia-glcore.so.$VERSION
            rsync -ah --progress $LOGIN_INFO:/wanliz_sw_windows_wsl2/workingbranch/drivers/OpenGL/win/egl/build/_out/Linux_${ARCH}_${CONFIG}/libnvidia-eglcore.so $RSYNC_DST/libnvidia-eglcore.so.$VERSION 
            rsync -ah --progress $LOGIN_INFO:/wanliz_sw_windows_wsl2/workingbranch/drivers/OpenGL/win/egl/glsi/_out/Linux_${ARCH}_${CONFIG}/libnvidia-glsi.so $RSYNC_DST/libnvidia-glsi.so.$VERSION 
            rsync -ah --progress $LOGIN_INFO:/wanliz_sw_windows_wsl2/workingbranch/drivers/OpenGL/win/unix/tls/Linux-elf/_out/Linux_${ARCH}_${CONFIG}/libnvidia-tls.so $RSYNC_DST/libnvidia-tls.so.$VERSION 
            rsync -ah --progress $LOGIN_INFO:/wanliz_sw_windows_wsl2/workingbranch/drivers/OpenGL/win/glx/lib/_out/Linux_${ARCH}_${CONFIG}/libGLX_nvidia.so $RSYNC_DST/libGLX_nvidia.so.$VERSION  
            rsync -ah --progress $LOGIN_INFO:/wanliz_sw_windows_wsl2/workingbranch/drivers/khronos/egl/egl/_out/Linux_${ARCH}_${CONFIG}/libEGL_nvidia.so $RSYNC_DST/libEGL_nvidia.so.$VERSION  
            
            if [[ ! -e /usr/lib/$(uname -m)-linux-gnu/libnvidia-glcore.so.$VERSION ]]; then 
                echo "Incompatible version $VERSION"
                exit 1
            fi 

            if [[ $NOSYSDIR == 1 ]]; then
                echo 
                echo "LD_LIBRARY_PATH=$HOME/NVIDIA-Linux-$(uname -m)-${CONFIG}-${VERSION}-internal${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH} ..." 
            else 
                read -p "Press [Enter] to continue: "
                if [[ -f $HOME/libnvidia-glcore.so.$VERSION.backup ]]; then 
                    echo "Reuse existing backups"
                else
                    sudo cp /usr/lib/$(uname -m)-linux-gnu/libnvidia-glcore.so.$VERSION $HOME/libnvidia-glcore.so.$VERSION.backup
                    sudo cp /usr/lib/$(uname -m)-linux-gnu/libnvidia-eglcore.so.$VERSION $HOME/libnvidia-eglcore.so.$VERSION.backup
                    sudo cp /usr/lib/$(uname -m)-linux-gnu/libnvidia-glsi.so.$VERSION $HOME/libnvidia-glsi.so.$VERSION.backup
                    sudo cp /usr/lib/$(uname -m)-linux-gnu/libnvidia-tls.so.$VERSION $HOME/libnvidia-tls.so.$VERSION.backup
                    sudo cp /usr/lib/$(uname -m)-linux-gnu/libGLX_nvidia.so.$VERSION $HOME/libGLX_nvidia.so.$VERSION.backup
                    sudo cp /usr/lib/$(uname -m)-linux-gnu/libEGL_nvidia.so.$VERSION $HOME/libEGL_nvidia.so.$VERSION.backup
                fi 

                sudo cp -vf --remove-destination $HOME/libnvidia-glcore.so.$VERSION /usr/lib/$(uname -m)-linux-gnu/libnvidia-glcore.so.$VERSION
                sudo cp -vf --remove-destination $HOME/libnvidia-eglcore.so.$VERSION /usr/lib/$(uname -m)-linux-gnu/libnvidia-eglcore.so.$VERSION
                sudo cp -vf --remove-destination $HOME/libnvidia-glsi.so.$VERSION /usr/lib/$(uname -m)-linux-gnu/libnvidia-glsi.so.$VERSION
                sudo cp -vf --remove-destination $HOME/libnvidia-tls.so.$VERSION /usr/lib/$(uname -m)-linux-gnu/libnvidia-tls.so.$VERSION
                sudo cp -vf --remove-destination $HOME/libGLX_nvidia.so.$VERSION /usr/lib/$(uname -m)-linux-gnu/libGLX_nvidia.so.$VERSION
                sudo cp -vf --remove-destination $HOME/libEGL_nvidia.so.$VERSION /usr/lib/$(uname -m)-linux-gnu/libEGL_nvidia.so.$VERSION
            fi # if [[ $NOSYSDIR == 1 ]]
        fi # if [[ $RESTORE == 1 ]]
    fi # if [[ $TARGET == opengl ]]
else 
    if sudo test ! -d /root/nvt; then 
        sudo /mnt/linuxqa/nvt.sh sync
    fi 
    sudo env NVTEST_INSTALLER_REUSE_INSTALL=False /mnt/linuxqa/nvt.sh drivers "$@" 2>/tmp/std2 
    cat /tmp/std2
    driver_src=$(cat /tmp/std2 | grep 'NVTEST_DRIVER=' | awk '{print $2}' | awk -F'=' '{print $2}')
    driver_dst=$HOME/$(basename "$driver_src")
    if [[ ! -z $driver_src ]]; then 
        if [[ "$driver_src" == http* ]]; then 
            sudo cp -vf /root/nvt/driver/$(basename "$driver_src") $driver_dst || exit 1
            sudo cp -vf /root/nvt/driver/tests-Linux-$(uname -m).tar $(dirname $driver_dst)
            echo "$driver_dst" > $HOME/.driver 
            echo "Generated $HOME/.driver"
        elif [[ -f $driver_src ]]; then 
            echo "$driver_src" > $HOME/.driver 
            echo "Generated $HOME/.driver"
        fi 
    fi 
fi 