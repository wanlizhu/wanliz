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
        linux $ARCH $CONFIG -Bn -j$(nproc) >/tmp/nvmake.out 2>/tmp/nvmake.err && {
        cat /tmp/nvmake.out |  
        grep "set -e.*gcc.*-c" | 
        sed 's/^.*set -e ; *//' |  
        sed 's/ ; \/bin\/sed.*//' |
        sed 's|^[^ ]*/gcc[^ ]* ||' |
        sed 's/^/clang /' > _out/$Linux_arch_config/compile_commands.json && 
        echo "Generated  _out/$Linux_arch_config/compile_commands.json"
    } || {
        cat /tmp/nvmake.err 
        exit 1
    }

    num_commands=$(wc -l  < _out/$Linux_arch_config/compile_commands.json)
    echo "Found $num_commands compile commands"
    if [[ $num_commands == 0 ]]; then
        exit 1
    fi 

    function resolve_gch_header() {
        if [[ -f $NV_SOURCE/drivers/OpenGL/_out/$Linux_arch_config/pch/$(basename "$1").gch ]]; then 
            cat $NV_SOURCE/drivers/OpenGL/_out/$Linux_arch_config/pch/$(basename "$1").gch.cmd | awk -v wd="" '{
                if (NR==1) wd=$1
                for (i=5;i<=NF;i++) {
                    t=$i
                    if (t=="-include" || t=="-isystem") { 
                        i++; p=$(i)
                        if (p !~ /^\//) p = wd "/" p
                        out = out sep t " " p; sep=" "
                        continue 
                    }
                    if (t ~ /^-I/) { 
                        p=substr(t,3)
                        if (p !~ /^\//) p = wd "/" p
                        out = out sep "-I" p; sep=" "
                        continue
                    }
                    if (t ~ /^-D/) { out = out sep t; sep=" " }
                }
            } END { if (out!="") printf "%s", out }' > /tmp/gch.cmd
            echo "$1 $(cat /tmp/gch.cmd)"
        else
            echo "$1"
        fi 
    }

    function resolve_include_path() {
        path="$1"
        if [[ "$path" != /* ]]; then
            if [[ -e "$NV_SOURCE/drivers/OpenGL/$path" ]]; then 
                path="$NV_SOURCE/drivers/OpenGL/$path"
            elif [[ -e "$NV_SOURCE/drivers/OpenGL/_out/$Linux_arch_config/$path" ]]; then 
                path="$NV_SOURCE/drivers/OpenGL/_out/$Linux_arch_config/$path"
            else
                echo "$path doesn't exist" >&2
                exit 1
            fi 
        fi
        resolve_gch_header "$path"
    }

    echo "[" > compile_commands.json
    command_index=0
    while IFS= read -r line; do 
        (( command_index += 1 ))
        printf '\r\033[KNormalizing %s/%s arguments for clangd ... ' "$command_index" "$num_commands"
        [[ $command_index == $num_commands ]] && echo 

        [[ -z $line ]] && continue 
        srcfile=$(echo "$line" | grep -oE '\-c +[^ ]+\.(c|cpp|cc|cxx)' | sed 's/-c *//' | head -1)
        if [[ -z "$srcfile" ]]; then
            srcfile=$(echo "$line" | grep -oE '[^ ]+\.(c|cpp|cc|cxx)' | head -1)
        fi
        [[ -z "$srcfile" ]] && continue
        [[ "$srcfile" != /* ]] && srcfile="$NV_SOURCE/drivers/OpenGL/$srcfile"
        (( command_index > 1 )) && echo "," >> compile_commands.json

        command=$(echo "$line" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g')
        clang_cmdline=""
        skip_next=
        include_next=

        for cmdpart in $command; do 
            if [[ $include_next == 1 ]]; then
                include_next=
                include_path=$(resolve_include_path "$cmdpart")
                clang_cmdline+=" $include_path"
                continue
            fi
            if [[ $skip_next == 1 ]]; then 
                skip_next=
                continue
            fi
            cmdpart_ignore=
            for arg in  "-gas-loc-support" \
                        "-Wformat-overflow" \
                        "-Wformat-truncation" \
                        "-Wno-error=" \
                        "-Wno-class-memaccess" \
                        "-Wno-stringop-truncation" \
                        "-Winvalid-pch" \
                        "-Wno-format-zero-length" \
                        "-nostdinc" \
                        "-march=" \
                        "-mtune=" \
                        "-mfpmath=" \
                        "-mstackrealign" \
                        "-flto=" \
                        "-fasynchronous-unwind-tables" \
                        "--sysroot="; do 
                case $cmdpart in 
                    "$arg"|"$arg"*) cmdpart_ignore=1 ;;
                esac
            done 
            if [[ $cmdpart == "-MF" || $cmdpart == "-MT" || $cmdpart == "-o" ]]; then 
                skip_next=1
                continue
            fi
            if [[ $cmdpart == "-MF"* || $cmdpart == "-MT"* || $cmdpart == "-o"* ]]; then 
                continue
            fi
            if [[ $cmdpart == "-I" ]]; then
                clang_cmdline+=" -I"
                include_next=1
                continue
            fi
            if [[ $cmdpart == "-I"* ]]; then 
                path=$(resolve_include_path "${cmdpart#-I}")
                cmdpart="-I$path"
            fi 
            if [[ $cmdpart == "-include" ]]; then # GCC required a space after
                clang_cmdline+=" -include"
                include_next=1
                continue
            fi
            if [[ $cmdpart == "-isystem" ]]; then # GCC required a space after
                clang_cmdline+=" -isystem"
                include_next=1
                continue
            fi
            if [[ $cmdpart == "-B"* ]]; then 
                continue 
            fi
            if [[ $cmdpart == *"binutils-"* ]]; then 
                continue 
            fi 
            if [[ $cmdpart_ignore == 1 ]]; then 
                continue 
            fi 
            clang_cmdline+=" $cmdpart"
        done 
        echo "{" >> compile_commands.json
        echo "    \"directory\": \"$NV_SOURCE/drivers/OpenGL\"," >> compile_commands.json
        echo "    \"command\": \"$clang_cmdline\"," >> compile_commands.json
        echo "    \"file\": \"$srcfile\"" >> compile_commands.json
        echo "}" >> compile_commands.json
    done < _out/$Linux_arch_config/compile_commands.json
    echo ""  >> compile_commands.json
    echo "]" >> compile_commands.json
    echo "Generated  compile_commands.json"
fi 