#!/usr/bin/env bash
trap 'exit 130' INT

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
TARGET_INSTALL=
CONFIG=develop
ARCH=$(uname -m | sed 's/x86_64/amd64/g')
SINGLE_THREAD=
NOBUILD=
CLEAN_BUILD=
CC=
EXTRA_ARGS=
while [[ ! -z $1 ]]; do 
    case $1 in 
        debug|release|develop) CONFIG=$1 ;;
        amd64|x64|x86_64) ARCH=amd64 ;;
        aarch64|arm64) ARCH=aarch64 ;;
        opengl)  TARGET="opengl"; TARGET_INSTALL=opengl ;;
        drivers) TARGET="drivers dist"; TARGET_INSTALL=drivers ;;
        -j1) SINGLE_THREAD="-j1" ;;
        -cc) CC=1 ;;
        -n) NOBUILD=1 ;;
        -clean) CLEAN_BUILD=1 ;;
        *) EXTRA_ARGS+=" $1" ;;
    esac
    shift 
done 

if [[ -z $P4ROOT ]]; then 
    export P4PORT="p4proxy-sc.nvidia.com:2006"
    export P4USER="wanliz"
    export P4CLIENT="wanliz_sw_windows_wsl2"
    export P4ROOT="/wanliz_sw_windows_wsl2"
fi 

if [[ -z $TARGET ]]; then 
    if [[ -f makefile.nvmk ]]; then 
        echo "Builing $(pwd)"
    else 
        echo "makefile.nvmk doesn't exist"
        exit 1
    fi 
else 
    cd $P4ROOT/workingbranch || exit 1
fi 

if [[ -z $NOBUILD ]]; then 
    if [[ $TARGET == opengl ]]; then 
        pushd $P4ROOT/workingbranch/drivers/OpenGL/win/egl/glsi >/dev/null 
        wanliz-nvmake $ARCH $CONFIG $SINGLE_THREAD || exit 1
        popd >/dev/null 

        pushd $P4ROOT/workingbranch/drivers/OpenGL/win/unix/tls/Linux-elf >/dev/null 
        wanliz-nvmake $ARCH $CONFIG $SINGLE_THREAD || exit 1
        popd >/dev/null 

        pushd $P4ROOT/workingbranch/drivers/OpenGL/win/glx/lib >/dev/null 
        wanliz-nvmake $ARCH $CONFIG $SINGLE_THREAD || exit 1
        popd >/dev/null 

        pushd $P4ROOT/workingbranch/drivers/OpenGL/win/egl/build >/dev/null 
        wanliz-nvmake $ARCH $CONFIG $SINGLE_THREAD || exit 1
        popd >/dev/null 

        pushd $P4ROOT/workingbranch/drivers/OpenGL >/dev/null 
        wanliz-nvmake $ARCH $CONFIG $SINGLE_THREAD || exit 1
        popd >/dev/null 
        echo 
    else 
        if [[ $CLEAN_BUILD == 1 ]]; then 
            rm -rf _out/Linux_${ARCH}_${CONFIG}
            echo "Removed _out/Linux_${ARCH}_${CONFIG}"
        fi 
        if [[ ! -z $SINGLE_THREAD ]]; then 
            JOBS="-j1"
        else
            JOBS="-j$(nproc)"
        fi 
        time $P4ROOT/tools/linux/unix-build/unix-build \
            --unshare-namespaces \
            --tools  $P4ROOT/tools \
            --devrel $P4ROOT/devrel/SDK/inc/GL \
            nvmake \
            NV_COLOR_OUTPUT=1 \
            NV_GUARDWORD=0 \
            NV_COMPRESS_THREADS=$(nproc) \
            NV_FAST_PACKAGE_COMPRESSION=zstd \
            NV_USE_FRAME_POINTER=1 \
            NV_UNIX_LTO_ENABLED=0 \
            NV_LTCG=0 \
            NV_UNIX_CHECK_DEBUG_INFO=0 \
            NV_MANGLE_SYMBOLS=0 \
            NV_TRACE_CODE=$([[ $CONFIG == release ]] && echo 0 || echo 1) \
            linux $TARGET $ARCH $CONFIG $JOBS $EXTRA_ARGS || exit 1
        echo 
    fi 
    
    if [[ ! -z $TARGET_INSTALL ]]; then 
        myip=$(ip -4 route get $(getent ahostsv4 1.1.1.1 | awk 'NR==1{print $1}') | sed -n 's/.* src \([0-9.]\+\).*/\1/p')
        nvsrc_version=$(sed -n 's/^[[:space:]]*#define[[:space:]]\+NV_VERSION_STRING[[:space:]]\+"\([^"]\+\)".*/\1/p' /wanliz_sw_windows_wsl2/workingbranch/drivers/common/inc/nvUnixVersion.h | head -n1)
        echo "wanliz-install-driver $USER@$myip $TARGET_INSTALL $ARCH $CONFIG $nvsrc_version"
        echo 
    fi 

    if [[ $CONFIG == debug ]]; then
        echo "Bypass debug assert: __GL_DEBUG_BYPASS_ASSERT=Ignore"
        echo 
    fi 
fi 

if [[ $CC == 1 ]]; then 
    Linux_arch_config=Linux_${ARCH}_${CONFIG}
    echo "Generating _out/$Linux_arch_config/compile_commands.json"
    rm -f /tmp/nvmake.out /tmp/nvmake.err 
    rm -f _out/$Linux_arch_config/compile_commands.json compile_commands.json 

    cd $P4ROOT/workingbranch/drivers/OpenGL || exit 1
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