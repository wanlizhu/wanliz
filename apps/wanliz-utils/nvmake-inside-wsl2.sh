#!/usr/bin/env bash

export P4PORT="p4proxy-sc.nvidia.com:2006"
export P4USER="wanliz"
export P4CLIENT="wanliz_sw_windows"
export P4ROOT="/mnt/d/wanliz_sw_windows"
export P4IGNORE="$HOME/.p4ignore"

arch=amd64
config=develop
jobs=$(nproc)
fixfiles=
args=
while [[ ! -z $1 ]]; do 
    case $1 in 
        debug|release|develop) config=$1 ;;
        amd64|x64|x86_64) arch=amd64 ;;
        aarch64|arm64) arch=aarch64 ;; 
        -j1) jobs=1 ;;
        -fix) fixfiles=1 ;;
        *) args="$args $1" ;;
    esac
    shift 
done 

if [[ $fixfiles == 1 ]]; then 
    [[ -z $(which dos2unix) ]] && sudo apt install -y dos2unix 
    [[ -z $(which parallel) ]] && sudo apt install -y parallel

    echo "Fixing symlinks in /mnt/d/wanliz_sw_windows/..."
    p4 files //wanliz_sw_windows/... | grep "(symlink)" | awk -F'#' '{print $1}' | parallel -j $(nproc) '
        depot_file="{}"
        local_file=$(p4 where "$depot_file" 2>/dev/null | awk "{print \$3}")
        target=$(p4 print -q "$depot_file" 2>/dev/null | tr -d '"'"'\r'"'"')
        if [ ! -z "$local_file" ] && [ ! -z "$target" ]; then 
            wsl_file=$(wslpath "$local_file" 2>/dev/null || echo "$local_file")
            [ -L "$wsl_file" ] && exit 0
            dir=$(dirname "$wsl_file")
            name=$(basename "$wsl_file")
            cd "$dir" && rm -f "$name" && ln -s "$target" "$name" && echo "Fixed symlink $wsl_file"
        fi 
    '

    echo "Fixing file ending in /mnt/d/wanliz_sw_windows/workingbranch/..."
    find "/mnt/d/wanliz_sw_windows/workingbranch" \( -path "*/_out" -o -path "*/_doc" -o -path "*/.git" \) -prune -o -type f \( \
        -name "*.sh" -o -name "*.bash" -o \
        -name "*.py" -o -name "*.pl" -o -name "*.cmd" -o \
        -name "*.cfg" -o -name "*.conf" -o -name "*.config" -o \
        -name "*.nvmk" -o -name "Makefile*" -o -name "*.mk" -o -name "*.cmake" -o \
        -name "*.pm" -o -name "*.rb" -o \
        -name "*.yaml" -o -name "*.xml" -o -name "*.json" \
    \) -print | parallel -j $(nproc) '
        if [ -n "$(dos2unix -ic {} 2>/dev/null)" ]; then 
            dos2unix {} >/dev/null 2>&1 && echo "Fixed line ending {}"
        fi
    ' 
fi 

echo "Syncing from NTFS to EXT4 ..."
rsync -aHAX --delete --info=progress2 --exclude='_out/' --exclude='.git/' "$P4ROOT/" "$HOME/wanliz_sw_windows/" || exit 1


cd   $HOME/wanliz_sw_windows/workingbranch/drivers/OpenGL &&  
time $HOME/wanliz_sw_windows/tools/linux/unix-build/unix-build \
    --tools $HOME/wanliz_sw_windows/tools \
    --devrel $HOME/wanliz_sw_windows/devrel/SDK/inc/GL \
    nvmake \
    NV_COLOR_OUTPUT=1 \
    NV_GUARDWORD= \
    NV_COMPRESS_THREADS=$(nproc) \
    NV_FAST_PACKAGE_COMPRESSION=zstd \
    NV_USE_FRAME_POINTER=1 \
    NV_UNIX_LTO_ENABLED= \
    NV_LTCG= \
    NV_UNIX_CHECK_DEBUG_INFO=0 \
    NV_MANGLE_SYMBOLS= \
    NV_TRACE_CODE=1 \
    linux $arch $config $args -j$jobs


echo "Syncing from EXT4 to NTFS ..."
rsync -aHAX --info=progress2 "$HOME/wanliz_sw_windows/workingbranch/drivers/OpenGL/_out/" "$P4ROOT/workingbranch/drivers/OpenGL/_out/"