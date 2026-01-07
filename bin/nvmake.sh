#!/usr/bin/env bash
trap 'exit 130' INT
if [[ $EUID == 0 || -z $(which sudo) ]]; then 
    sudo() { "$@"; }
fi 

if [[ -z $P4ROOT ]]; then 
    export P4ROOT="/home/wanliz/sw"
fi 

#echo -e "Todo: p4 revert -k -c default /home/wanliz/sw/... \t Abandon records but keep local changes"
#echo -e "Todo: p4 sync --parallel=threads=32 $P4ROOT/branch/...@12345678 \t Sync to specified CL"
#echo -e "Todo: p4 reconcile -f -m -M --parallel=32 -c default $P4ROOT/... \t P4v's reconcile"

if [[ $1 == -h || $1 == --help ]]; then 
    echo "Usage: $0 [BRANCH] [TARGET] [ARCH] [CONFIG] [options] [-- extra nvmake args]"
    echo ""
    echo "BRANCH:  all, bugfix_main, r580_00, r590_00, ..."
    echo "TARGET:  opengl, drivers, (run in cwd if not specified)"
    echo "  ARCH:  amd64 (default), aarch64"
    echo "CONFIG:  develop (default), debug, release"
    echo ""
    echo "Options:"
    echo "  -j[0-9]*               build with N jobs (default: $(nproc))"
    echo "  --cleanbuild           make a clean build (remove _out/Linux_arch_config) first"
    echo "  --regen-clangd-db      generate compile_commands.json"
    echo "  --gen-code             build @generate target"
    echo "  --regen-code           build @regenerate target"
    echo "Any other arguments are passed through as NVMAKE_EXTRA_ARGS to nvmake."
    exit 0
fi

BRANCH=
TARGET=
ARCH=$(uname -m | sed 's/x86_64/amd64/g')
CONFIG=develop
THREADS=$(nproc)
CLEAN_BUILD=
REGEN_CLANGD_DB=
GENERATE=
NVMAKE_EXTRA_ARGS=
DUPLICATED_BRANCH_ARGS=
while [[ ! -z $1 ]]; do 
    case $1 in 
        all|bugfix_main|r*)    BRANCH=$1 ;;
        drivers|opengl|glcore) TARGET=$1;                   DUPLICATED_BRANCH_ARGS+=" $1" ;;
        amd64|aarch64)         ARCH=$1;                     DUPLICATED_BRANCH_ARGS+=" $1" ;;
        debug|release|develop) CONFIG=$1;                   DUPLICATED_BRANCH_ARGS+=" $1" ;;
        -j[0-9]*)              THREADS=${1#-j};             DUPLICATED_BRANCH_ARGS+=" $1" ;;
        --cleanbuild)          CLEAN_BUILD="$1";            DUPLICATED_BRANCH_ARGS+=" $1" ;;
        --regen-clangd-db)     REGEN_CLANGD_DB="$1";        DUPLICATED_BRANCH_ARGS+=" $1" ;;
        --gen-code)            GENERATE="@generate";        DUPLICATED_BRANCH_ARGS+=" $1" ;;
        --regen-code)          GENERATE="@regenerate";      DUPLICATED_BRANCH_ARGS+=" $1" ;;
        *)                     NVMAKE_EXTRA_ARGS+=" $1";    DUPLICATED_BRANCH_ARGS+=" $1" ;;
    esac
    shift 
done 

if [[ -z $TARGET ]]; then 
    if [[ -f makefile.nvmk ]]; then 
        echo "Builing $(pwd)"
    else 
        echo "makefile.nvmk doesn't exist"
        exit 1
    fi 
else 
    if [[ $BRANCH == all ]]; then 
        find $P4ROOT/branch -mindepth 1 -maxdepth 1 -type d -print '%f\n' | 
        while IFS= read -r branch_name; do 
            nvmake $branch_name $DUPLICATED_BRANCH_ARGS || exit 1
        done 
        exit 0
    fi 
    
    if [[ -z $BRANCH ]]; then 
        count=$(find $P4ROOT/branch -mindepth 1 -maxdepth 1 -type d -print | wc -l)
        if (( count > 1 )); then
            find $P4ROOT/branch -mindepth 1 -maxdepth 1 -type d -printf '%f\t'; echo
            read -p "Which branch to build: " BRANCH
        elif (( count == 1 )); then 
            BRANCH=$(find $P4ROOT/branch -mindepth 1 -maxdepth 1 -type d -printf '%f\n')
        else
            echo "$P4ROOT/branch/... is empty"
            exit 1
        fi 
    fi 

    if [[ -d $P4ROOT/branch/$BRANCH ]]; then 
        echo "Located $P4ROOT/branch/$BRANCH"
    else
        echo "$P4ROOT/branch/$BRANCH doesn't exist"
    fi 

    cd $P4ROOT/branch/$BRANCH || exit 1
fi 

if [[ $TARGET == opengl ]]; then 
    pushd $P4ROOT/branch/$BRANCH/drivers/OpenGL >/dev/null || exit 1
    if [[ ! -z $GENERATE ]]; then 
        nvmake $ARCH $CONFIG -j$THREADS $CLEAN_BUILD $GENERATE $NVMAKE_EXTRA_ARGS || exit 1
    fi 
    nvmake $ARCH $CONFIG -j$THREADS $CLEAN_BUILD $REGEN_CLANGD_DB $NVMAKE_EXTRA_ARGS || exit 1
    popd >/dev/null 

    pushd $P4ROOT/branch/$BRANCH/drivers/OpenGL/win/egl/build >/dev/null || exit 1
    if [[ ! -z $GENERATE ]]; then 
        nvmake $ARCH $CONFIG -j$THREADS $CLEAN_BUILD $GENERATE $NVMAKE_EXTRA_ARGS || exit 1
    fi 
    nvmake $ARCH $CONFIG -j$THREADS $CLEAN_BUILD $NVMAKE_EXTRA_ARGS || exit 1
    popd >/dev/null 

    pushd $P4ROOT/branch/$BRANCH/drivers/OpenGL/win/egl/glsi >/dev/null || exit 1
    nvmake $ARCH $CONFIG -j$THREADS $CLEAN_BUILD $NVMAKE_EXTRA_ARGS || exit 1
    popd >/dev/null 

    pushd $P4ROOT/branch/$BRANCH/drivers/OpenGL/win/unix/tls/Linux-elf >/dev/null || exit 1
    nvmake $ARCH $CONFIG -j$THREADS $CLEAN_BUILD $NVMAKE_EXTRA_ARGS || exit 1
    popd >/dev/null 

    pushd $P4ROOT/branch/$BRANCH/drivers/OpenGL/win/glx/lib >/dev/null || exit 1
    nvmake $ARCH $CONFIG -j$THREADS $CLEAN_BUILD $NVMAKE_EXTRA_ARGS || exit 1
    popd >/dev/null 

    pushd $P4ROOT/branch/$BRANCH/drivers/khronos/egl/egl >/dev/null || exit 1
    nvmake $ARCH $CONFIG -j$THREADS $CLEAN_BUILD $NVMAKE_EXTRA_ARGS || exit 1
    popd >/dev/null 
    echo 
elif [[ $TARGET == glcore ]]; then 
    pushd $P4ROOT/branch/$BRANCH/drivers/OpenGL >/dev/null 
    nvmake $ARCH $CONFIG -j$THREADS $CLEAN_BUILD $NVMAKE_EXTRA_ARGS || exit 1
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
        linux $TARGET $([[ $TARGET == drivers ]] && echo dist) $([[ $(dirname $(pwd)) == OpenGL ]] && echo '@generate') \
        $ARCH $CONFIG -j$THREADS $NVMAKE_EXTRA_ARGS \
        2>/tmp/nvmake.err || {
            cat /tmp/nvmake.err
            echo 
            echo "============ NVMAKE ERRORS ============"
            cat /tmp/nvmake.err | grep ': \*\*\*'
            exit 1
        }
    echo  
fi 

if [[ ! -z $REGEN_CLANGD_DB && $(basename $(pwd)) == OpenGL ]]; then 
    echo "Generating _out/Linux_${ARCH}_${CONFIG}/compile_commands.json"
    mkdir -p _out/Linux_${ARCH}_${CONFIG}
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
        linux $ARCH $CONFIG -Bn -j$(nproc) > _out/Linux_${ARCH}_${CONFIG}/gcc_compile_commands.txt 2>/dev/null 
        
    if [[ -f _out/Linux_${ARCH}_${CONFIG}/gcc_compile_commands.txt ]]; then 
        echo "Generated  _out/Linux_${ARCH}_${CONFIG}/gcc_compile_commands.txt"
        process-clangd-database _out/Linux_${ARCH}_${CONFIG}/gcc_compile_commands.txt
        if [[ -f compile_commands.json ]]; then 
            echo "Generated compile_commands.json"
        fi 
    else
        echo "Failed to generate _out/Linux_${ARCH}_${CONFIG}/gcc_compile_commands.txt"
    fi 
fi 

if [[ $TARGET == drivers || $TARGET == opengl ]]; then 
    MY_IP=$(ip -4 route get $(getent ahostsv4 1.1.1.1 | awk 'NR==1{print $1}') | sed -n 's/.* src \([0-9.]\+\).*/\1/p')
    NVSRC_VERSION=$(sed -n 's/^[[:space:]]*#define[[:space:]]\+NV_VERSION_STRING[[:space:]]\+"\([^"]\+\)".*/\1/p' /home/wanliz/sw/branch/$BRANCH/drivers/common/inc/nvUnixVersion.h | head -n1)
    echo "install-nvidia-driver $USER@$MY_IP $BRANCH $TARGET $ARCH $CONFIG $NVSRC_VERSION --nosudo"
fi 

if [[ $CONFIG == debug ]]; then
    echo "Bypass debug assert: __GL_DEBUG_BYPASS_ASSERT=Ignore"
fi 

echo 