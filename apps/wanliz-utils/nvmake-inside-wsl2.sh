#!/usr/bin/env bash

if [[ -z $P4CLIENT ]]; then 
    eval "$(p4env.sh -print)"
fi 

arch=amd64
config=develop
jobs=$(nproc)
fixfiles=
cmdline_args=
while [[ ! -z $1 ]]; do 
    case $1 in 
        debug|release|develop) config=$1 ;;
        amd64|x64|x86_64) arch=amd64 ;;
        aarch64|arm64) arch=aarch64 ;; 
        -j1) jobs=1 ;;
        -fix) fixfiles=1 ;;
        *) cmdline_args+=" $1" ;;
    esac
    shift 
done 

if [[ $fixfiles == 1 ]]; then 
    [[ -z $(which dos2unix) ]] && sudo apt install -y dos2unix 
    [[ -z $(which parallel) ]] && sudo apt install -y parallel
    function fix_symlink {
        depot_file="$1"
        local_file=$(p4 where "$depot_file" 2>/dev/null | awk '{print $3}')
        target=$(p4 print -q "$depot_file" 2>/dev/null | tr -d '\r')
        if [[ ! -z "$local_file" && ! -z "$target" ]]; then 
            wsl_file=$(wslpath "$local_file" 2>/dev/null || echo "$local_file")
            [[ -L "$wsl_file" ]] && continue
            dir=$(dirname "$wsl_file")
            name=$(basename "$wsl_file")
            cd "$dir" && rm -f "$name" && ln -s "$target" "$name" && echo "Fixed symlink $wsl_file"
        fi 
    }
    export -f fix_symlink

    echo "Fixing symlinks in //wanliz_sw_windows/..."
    p4 files //wanliz_sw_windows/... | grep "(symlink)" | parallel -j $(nproc) fix_symlink {}  

    echo "Fixing file ending in //wanliz_sw_windows/..."
    find "/mnt/d/wanliz_sw_windows/workingbranch" \( -path "*/_out" -o -path "*/_doc" -o -path "*/.git" \) -prune -o -type f \( \
        -name "*.sh" -o \
        -name "*.bash" -o \
        -name "*.py" -o \
        -name "*.pl" -o \
        -name "*.pm" -o \
        -name "*.nvmk" -o \
        -name "*.mk" -o \
        -name "*.rb" -o \
        -name "Makefile*" \
    \) -print | parallel -j $(nproc) 'dos2unix {} 2>/dev/null && echo "Fixed line ending {}"' 
fi 

cd $P4ROOT/workingbranch/drivers/OpenGL  
$P4ROOT/tools/linux/unix-build/unix-build \
    --tools $P4ROOT/tools \
    --devrel $P4ROOT/devrel/SDK/inc/GL \
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
    linux $arch $config $cmdline_args -j$jobs

