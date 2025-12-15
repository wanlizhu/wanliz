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
    echo "  -n           no real build"
    echo ""
    echo "Any other arguments are passed through as EXTRA_ARGS to nvmake."
    exit 0
fi

TARGET=
CONFIG=develop
ARCH=$(uname -m | sed 's/x86_64/amd64/g')
JOBS=$(nproc)
NOBUILD=
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
        -n) NOBUILD=1 ;;
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

if [[ -z $NOBUILD ]]; then 
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
        linux $TARGET $ARCH $CONFIG -j$JOBS $EXTRA_ARGS || exit 1
    echo 
fi 

if [[ $CC == 1 ]]; then 
    Linux_arch_config=Linux_${ARCH}_${CONFIG}
    echo "Generating _out/$Linux_arch_config/compile_commands.json"
    rm -f /tmp/nvmake.out /tmp/nvmake.err 
    rm -f _out/$Linux_arch_config/compile_commands.json compile_commands.json 

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
        linux $ARCH $CONFIG -Bn -j$(nproc) > _out/$Linux_arch_config/gcc_compile_commands.cmd && {
        echo "Generated  _out/$Linux_arch_config/gcc_compile_commands.cmd"
        wanliz-clangd-database _out/$Linux_arch_config/gcc_compile_commands.cmd
    } 
fi 