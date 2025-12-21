#!/usr/bin/env bash
trap 'exit 130' INT

if [[ $1 == -h || $1 == --help ]]; then 
    echo "Usage: $0 [BRANCH] [TARGET] [ARCH] [CONFIG] [options] [-- extra nvmake args]"
    echo ""
    echo "BRANCH:  workingbranch (default), testingbranch"
    echo "TARGET:  opengl, drivers, (run in cwd if not specified)"
    echo "  ARCH:  amd64 (default), aarch64"
    echo "CONFIG:  develop (default), debug, release"
    echo ""
    echo "Options:"
    echo "  -j[0-9]*     build with N jobs (default: $(nproc))"
    echo "  -c           make a clean build (remove _out/Linux_arch_config) first"
    echo "  -cc          generate compile_commands.json"
    echo ""
    echo "Any other arguments are passed through as EXTRA_ARGS to nvmake."
    exit 0
fi

BRANCH=workingbranch
TARGET=
TARGET_INSTALL=
ARCH=$(uname -m | sed 's/x86_64/amd64/g')
CONFIG=develop
THREADS=$(nproc)
CLEAN_BUILD=
COMPILE_COMMANDS=
EXTRA_ARGS=
while [[ ! -z $1 ]]; do 
    case $1 in 
        workingbranch|testingbranch) BRANCH=$1 ;;
        drivers) TARGET="drivers dist"; TARGET_INSTALL=drivers ;;
        opengl)  TARGET="opengl"; TARGET_INSTALL=opengl ;;
        glcore)  TARGET="glcore" ;;
        amd64|x64|x86_64) ARCH=amd64 ;;
        aarch64|arm64) ARCH=aarch64 ;;
        debug|release|develop) CONFIG=$1 ;;
        -j[0-9]*) THREADS=${1#-j} ;;
        -c|-clean) CLEAN_BUILD="-c" ;;
        -cc|-compilecommands) COMPILE_COMMANDS="-cc" ;;
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
    cd $P4ROOT/$BRANCH || exit 1
fi 

if [[ $TARGET == opengl ]]; then 
    pushd $P4ROOT/$BRANCH/drivers/OpenGL >/dev/null || exit 1
    wanliz-nvmake $ARCH $CONFIG -j$THREADS $CLEAN_BUILD $EXTRA_ARGS || exit 1
    popd >/dev/null 

    pushd $P4ROOT/$BRANCH/drivers/OpenGL/win/egl/build >/dev/null || exit 1
    wanliz-nvmake $ARCH $CONFIG -j$THREADS $CLEAN_BUILD $EXTRA_ARGS || exit 1
    popd >/dev/null 

    pushd $P4ROOT/$BRANCH/drivers/OpenGL/win/egl/glsi >/dev/null || exit 1
    wanliz-nvmake $ARCH $CONFIG -j$THREADS $CLEAN_BUILD $EXTRA_ARGS || exit 1
    popd >/dev/null 

    pushd $P4ROOT/$BRANCH/drivers/OpenGL/win/unix/tls/Linux-elf >/dev/null || exit 1
    wanliz-nvmake $ARCH $CONFIG -j$THREADS $CLEAN_BUILD $EXTRA_ARGS || exit 1
    popd >/dev/null 

    pushd $P4ROOT/$BRANCH/drivers/OpenGL/win/glx/lib >/dev/null || exit 1
    wanliz-nvmake $ARCH $CONFIG -j$THREADS $CLEAN_BUILD $EXTRA_ARGS || exit 1
    popd >/dev/null 

    pushd $P4ROOT/$BRANCH/drivers/khronos/egl/egl >/dev/null || exit 1
    wanliz-nvmake $ARCH $CONFIG -j$THREADS $CLEAN_BUILD $EXTRA_ARGS || exit 1
    popd >/dev/null 
    echo 
elif [[ $TARGET == glcore ]]; then 
    pushd $P4ROOT/$BRANCH/drivers/OpenGL >/dev/null 
    wanliz-nvmake $ARCH $CONFIG -j$THREADS $CLEAN_BUILD $EXTRA_ARGS || exit 1
    popd >/dev/null 
else 
    if [[ ! -z $CLEAN_BUILD ]]; then 
        rm -rf _out/Linux_${ARCH}_${CONFIG}
        echo "Removed _out/Linux_${ARCH}_${CONFIG}"
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
        linux $TARGET $ARCH $CONFIG -j$THREADS $EXTRA_ARGS || exit 1
    echo 
fi 

if [[ ! -z $TARGET_INSTALL ]]; then 
    MY_IP=$(ip -4 route get $(getent ahostsv4 1.1.1.1 | awk 'NR==1{print $1}') | sed -n 's/.* src \([0-9.]\+\).*/\1/p')
    NVSRC_VERSION=$(sed -n 's/^[[:space:]]*#define[[:space:]]\+NV_VERSION_STRING[[:space:]]\+"\([^"]\+\)".*/\1/p' /wanliz_sw_windows_wsl2/$BRANCH/drivers/common/inc/nvUnixVersion.h | head -n1)
    echo "wanliz-install-driver $USER@$MY_IP $BRANCH $TARGET_INSTALL $ARCH $CONFIG $NVSRC_VERSION"
    echo 
fi 

if [[ $CONFIG == debug ]]; then
    echo "Bypass debug assert: __GL_DEBUG_BYPASS_ASSERT=Ignore"
    echo 
fi 

if [[ ! -z $COMPILE_COMMANDS ]]; then 
    echo "Generating _out/Linux_${ARCH}_${CONFIG}/compile_commands.json"
    rm -f /tmp/nvmake.out /tmp/nvmake.err 
    rm -f _out/Linux_${ARCH}_${CONFIG}/compile_commands.json compile_commands.json 

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
        linux $ARCH $CONFIG -Bn -j$(nproc) > _out/Linux_${ARCH}_${CONFIG}/gcc_compile_commands.cmd && {
        echo "Generated  _out/Linux_${ARCH}_${CONFIG}/gcc_compile_commands.cmd"
        wanliz-clangd-database _out/Linux_${ARCH}_${CONFIG}/gcc_compile_commands.cmd
    } 
fi 