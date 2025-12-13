#!/usr/bin/env bash

if [[ $1 == -h || $1 == --help ]]; then 
    echo "Usage: $0 [CONFIG] [ARCH] [TARGET] [options] [-- extra nvmake args]"
    echo ""
    echo "CONFIG:  develop (default), debug, release"
    echo "  ARCH:  amd64 (default), aarch64"
    echo "TARGET:  opengl, drivers, (run in cwd if not specified)"
    echo ""
    echo "Options:"
    echo "  -j1          build with 1 job (default: $(nproc))"
    echo "  -cc          generate compile_commands.json"
    echo ""
    echo "Any other arguments are passed through as EXTRA_ARGS to nvmake."
    exit 0
fi

TARGET=
CONFIG=develop
ARCH=$(uname -m | sed 's/x86_64/amd64/g')
JOBS=$(nproc)
CC=
EXTRA_ARGS=
while [[ ! -z $1 ]]; do 
    case $1 in 
        debug|release|develop) CONFIG=$1 ;;
        amd64|x64|x86_64) ARCH=amd64 ;;
        aarch64|arm64) ARCH=aarch64 ;;
        opengl|sweep) TARGET=$1 ;;
        drivers) TARGET="drivers dist" ;;
        -j1) JOBS=1 ;;
        -cc) CC=1 ;;
        *) EXTRA_ARGS+=" $1" ;;
    esac
    shift 
done 

if [[ -d /wanliz_sw_linux ]]; then 
    export P4PORT="p4proxy-sc.nvidia.com:2006"
    export P4USER="wanliz"
    export P4CLIENT="wanliz_sw_linux"
    export P4ROOT="/wanliz_sw_linux"
    export NV_SOURCE="/wanliz_sw_linux/dev/gpu_drv/bugfix_main"
elif [[ -d /wanliz_sw_windows_wsl2 ]]; then 
    export P4PORT="p4proxy-sc.nvidia.com:2006"
    export P4USER="wanliz"
    export P4CLIENT="wanliz_sw_windows_wsl2"
    export P4ROOT="/wanliz_sw_windows_wsl2"
    export NV_SOURCE="/wanliz_sw_windows_wsl2/workingbranch"
fi 

if [[ -z $TARGET ]]; then 
    if [[ ! -f makefile.nvmk ]]; then 
        echo "makefile.nvmk doesn't exist"
        exit 1
    fi 
else 
    cd $NV_SOURCE || exit 1
fi 

time $P4ROOT/tools/linux/unix-build/unix-build \
    --unshare-namespaces \
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
    NV_TRACE_CODE=$([[ $CONFIG == release ]] && echo 0 || echo 1) \
    linux $TARGET $ARCH $CONFIG -j$JOBS $EXTRA_ARGS

if [[ $CC == 1 ]]; then 
    echo "Generating _out/compile_commands.json"
    rm -f /tmp/nvmake.out /tmp/nvmake.err 
    rm -f _out/compile_commands.json compile_commands.json
    cd $NV_SOURCE/drivers/OpenGL || exit 1
    $P4ROOT/tools/linux/unix-build/unix-build \
        --unshare-namespaces \
        --tools $P4ROOT/tools \
        --devrel $P4ROOT/devrel/SDK/inc/GL \
        nvmake \
        NV_COLOR_OUTPUT=0 \
        NV_TRACE_CODE=1 \
        NV_USE_FRAME_POINTER=1 \
        NV_GUARDWORD= \
        NV_MANGLE_SYMBOLS= \
        linux $ARCH $CONFIG -Bn >/tmp/nvmake.out 2>/tmp/nvmake.err && {
        cat /tmp/nvmake.out |  
        grep "set -e.*gcc.*-c" | 
        sed 's/^.*set -e ; *//' |  
        sed 's/ ; \/bin\/sed.*//' |  
        sed 's/^/clang /' > _out/compile_commands.json && 
        echo "Generated  _out/compile_commands.json"
    } || {
        cat /tmp/nvmake.err 
        exit 1
    }

    num_commands=$(wc -l  < _out/compile_commands.json)
    echo "Found $num_commands compile commands"
    if [[ $num_commands == 0 ]]; then
        exit 1
    fi 

    echo "Fixing command arguments for clang"
    echo "[" > compile_commands.json
    firstline=true
    while IFS= read -r line; do 
        [[ -z $line ]] && continue 
        srcfile=$(echo "$line" | grep -oE '\-c +[^ ]+\.(c|cpp|cc|cxx)' | sed 's/-c *//' | head -1)
        if [[ -z "$srcfile" ]]; then
            srcfile=$(echo "$line" | grep -oE '[^ ]+\.(c|cpp|cc|cxx)' | head -1)
        fi
        [[ -z "$srcfile" ]] && continue
        [[ "$srcfile" != /* ]] && srcfile="$NV_SOURCE/drivers/OpenGL/$srcfile"
        [[ "$firstline" == false ]] && echo "," >> compile_commands.json
        firstline=false
        command=$(echo "$line" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')
        command_cleaned=
        for cmdpart in $command; do 
            cmdpart_ignore=
            for arg in  "-gas-loc-support" \
                        "-Wformat-overflow" \
                        "-Wformat-truncation" \
                        "-Wno-error=" \
                        "-Wno-class-memaccess" \
                        "-Wno-stringop-truncation" \
                        "-nostdinc" \
                        "-march=" \
                        "-mtune=" \
                        "-mfpmath=" \
                        "--sysroot="; do 
                case $cmdpart in 
                    "$arg"|"$arg"*) cmdpart_ignore=1 ;;
                esac
            done 
            if [[ $cmdpart == "-isystem"* ]]; then 
                cmdpart="-I${cmdpart#-isystem}"
            fi 
            if [[ $cmdpart == "-I"* ]]; then 
                path=${cmdpart#-I}
                if [[ -d $NV_SOURCE/drivers/OpenGL/$path ]]; then 
                    cmdpart="-I$(realpath $NV_SOURCE/drivers/OpenGL/$path)"
                fi 
            fi 
            if [[ $cmdpart == *"/gcc-"* || $cmdpart == *"binutils-"* ]]; then 
                continue 
            fi 
            if [[ $cmdpart_ignore == 1 ]]; then 
                continue 
            fi 
            command_cleaned+=" $cmdpart"
        done 
        echo "{" >> compile_commands.json
        echo "    \"directory\": \"$NV_SOURCE/drivers/OpenGL\"," >> compile_commands.json
        echo "    \"command\": \"$command_cleaned\"," >> compile_commands.json
        echo "    \"file\": \"$srcfile\"" >> compile_commands.json
        echo "}" >> compile_commands.json
    done < _out/compile_commands.json
    echo ""  >> compile_commands.json
    echo "]" >> compile_commands.json
    echo "Generated  compile_commands.json"
fi 