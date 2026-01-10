#!/usr/bin/env bash
trap 'exit 130' INT
if [[ $EUID == 0 || -z $(which sudo) ]]; then 
    sudo() { "$@"; }
fi 

subcmd_backup_wsl2_home() {
    if [[ -d /mnt/d/wsl2_home.backup ]]; then
        rsync -ah --ignore-missing-args --delete --info=progress2 \
            $HOME/.bashrc \
            $HOME/.vimrc \
            $HOME/.screenrc \
            $HOME/.gitconfig \
            $HOME/.p4ignore \
            $HOME/.p4tickets \
            $HOME/.nv-tokens.yml \
            $HOME/.cursor/mcp.json \
            $HOME/.ssh \
            $HOME/.cursor \
            $HOME/wanliz \
            /mnt/d/wsl2_home.backup/
    else
        echo "/mnt/d/wsl2_home.backup/ doesn't exist"
    fi
}

subcmd_wanliz_git() {
    dst_dir=$HOME/wanliz
    if [[ ! -z $2 ]]; then 
        dst_dir=$(realpath $2)
    fi 
    if [[ -z "$(git config --global --get user.name)" ]]; then
        git config --global user.name "Wanli Zhu"
        git config --global user.email zhu.wanli@icloud.com
    fi
    if [[ -z $(cat $HOME/wanliz/.git/config | grep "wanlizhu/wanliz" | grep "@") ]]; then 
        if [[ -f /mnt/decode_password ]]; then 
            passwd=$(cat /tmp/decode_password)
        else 
            read -r -s -p "Decode Password: " passwd && echo 
        fi 
        token=$(echo 'U2FsdGVkX1/56ViCg37yZ/tFFpvGWW+3fYiKVCMeOiFfFrrQIhyg5ju0VUua8hAH8e7UKHbqYyJzJKvoz1opgg==' | openssl enc -d -aes-256-cbc -salt -pbkdf2 -a -k $passwd)
        sed -i "s#https://github.com#https://wanlizhu:${token}@github.com#g" $HOME/wanliz/.git/config
    fi 
    if [[ $1 == pull ]]; then 
        if [[ -d $dst_dir ]]; then
            pushd $dst_dir >/dev/null
            git add .
            git commit -m "$(date)"
            git pull
            popd >/dev/null
        else
            echo "$dst_dir doesn't exist"
        fi
    elif [[ $1 == push ]]; then
        if [[ -d $dst_dir ]]; then
            pushd $dst_dir >/dev/null
            git add .
            git commit -m "$(date)"
            git pull
            git push
            popd >/dev/null
        else
            echo "$dst_dir doesn't exist"
        fi
    fi 
}

subcmd_ip() {
    ip -4 route get $(getent ahostsv4 1.1.1.1 | awk 'NR==1{print $1}') | sed -n 's/.* src \([0-9.]\+\).*/\1/p'
}

subcmd_sw() {
    case $1 in 
        version) 
            find $HOME/sw/branch -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | 
            while IFS= read -r name; do 
                filename=$HOME/sw/branch/$name/drivers/common/inc/nvUnixVersion.h
                version=$(cat $filename | grep '#define NV_VERSION_STRING' | awk -F'"' '{print $2}')
                echo "~/sw/branch/$name -> $version"
            done  
        ;;
        *) echo "Error: unknown arg \"$1\" for zhu sw"; return 1 ;;
    esac 
}

subcmd_env() {
    if [[ -z $1 ]]; then 
        export P4PORT=p4proxy-sc.nvidia.com:2006
        export P4USER=wanliz
        export P4CLIENT=wanliz_sw_linux
        export P4ROOT=/home/wanliz/sw
        export P4IGNORE=$HOME/.p4ignore
        export NVM_GTLAPI_TOKEN='eyJhbGciOiJIUzI1NiJ9.eyJpZCI6IjNlMGZkYWU4LWM5YmUtNDgwOS1iMTQ3LTJiN2UxNDAwOTAwMyIsInNlY3JldCI6IndEUU1uMUdyT1RaY0Z0aHFXUThQT2RiS3lGZ0t5NUpaalU3QWFweUxGSmM9In0.Iad8z1fcSjA6P7SHIluppA_tYzOGxGv4koMyNawvERQ' 
        echo "Export env vars for P4 client: $P4CLIENT -- [OK]"
        echo "Export env var: NVM_GTLAPI_TOKEN -- [OK]"         
        if [[ -d /mnt/c/Users ]]; then 
            export P4CLIENT=wanliz_sw_windows_wsl2
            export GDK_SCALE=1
            export GDK_DPI_SCALE=1.25
            export QT_SCALE_FACTOR=1.25   
            echo "Export env vars for WSL2 -- [OK]"
        fi
    fi 

    for arg in "$@"; do 
        case $arg in 
            # UMD overrides
            umd) 
                export LD_LIBRARY_PATH=$HOME/NVIDIA-Linux-UMD-override${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH} 
                export VK_ICD_FILENAMES=$HOME/NVIDIA-Linux-UMD-override/nvidia_icd.json
                echo "Export env vars to enable umd overrides -- [OK]"
            ;;
            -umd)
                unset LD_LIBRARY_PATH
                unset VK_ICD_FILENAMES
                echo "Unset env vars to disable umd overrides -- [OK]"
            ;;
            # Enable pushbuffer dump
            pbd) 
                export __GL_ac12fedf=./pushbuffer-dump-%03d.xml 
                export __GL_ac12fede=0x10183
                echo "Export env vars to enable pushbuffer dump -- [OK]"
            ;;
            -pbd|-pushbuf|-pushbuffer-dump)
                unset __GL_ac12fedf
                unset __GL_ac12fede
                echo "Unset env vars to disable pushbuffer dump -- [OK]"
            ;;
            # Logs of RM calls
            rmlog) 
                export __GL_DEBUG_LEVEL=30 
                export __GL_DEBUG_MASK=RM
                echo "Export env vars to enable RM call logs -- [OK]"
            ;;
            -rmlog)
                unset __GL_DEBUG_LEVEL
                unset __GL_DEBUG_MASK
                echo "Unset env vars to disable RM call logs -- [OK]"
            ;;
            *) echo "Error: unknown arg \"$arg\" for \"zhu env\"" ;;
        esac 
    done  
}

subcmd_encrypt() {
    read -p "Password: " passwd
    echo "$1" | openssl enc -aes-256-cbc -salt -pbkdf2 -a -k $passwd
}

subcmd_decrypt() {
    read -p "Password: " passwd
    echo "$1" | openssl enc -d -aes-256-cbc -salt -pbkdf2 -a -k $passwd
}

rsync_host_io() {
    for ((i=1; i<$#; i++)); do 
        if [[ "${!i}" == from ]]; then
            j=$((i+1))
            rsync_host=${!j}
        fi 
    done  
    if [[ -z $rsync_host ]]; then 
        if [[ -f $HOME/.rsync_host ]]; then 
            read -e -i $(cat $HOME/.rsync_host) -p "Rsync Host: " rsync_host
        else
            read -p "Rsync Host: " rsync_host
        fi 
    fi 
    if [[ -z $rsync_host ]]; then 
        return 1
    fi 
    if [[ $rsync_host != *@* ]]; then 
        rsync_host="wanliz@$rsync_host"
        echo "Replacement: $rsync_host"
    fi 
    if [[ ! -f $HOME/.rsync_host_paired && -f $HOME/.ssh/id_ed25519 ]]; then 
        read -p "Enable passwordless login? [Yes/no]: " ssh_nopasswd
        if [[ $ssh_nopasswd =~ ^[[:space:]]*([yY]([eE][sS])?)?[[:space:]]*$ ]]; then
            ssh-copy-id $rsync_host && echo 1 > $HOME/.rsync_host_paired
        fi 
    fi 
    echo $rsync_host > $HOME/.rsync_host
}

subcmd_send() {
    rsync_host_io $@ || return 1
}

rsync_recv_vulkanbench() {
    rsync_host_io $@ || return 1 
    if [[ $(uname -m) == aarch64 ]]; then 
        rsync -Pah $rsync_host:/home/wanliz/wanliz/build-linux-aarch64/vulkanbench . 
    elif [[ $(uname -m) == x86_64 ]]; then 
        rsync -Pah $rsync_host:/home/wanliz/wanliz/build-linux/vulkanbench . 
    fi 
}

rsync_nvsrc_io() {
    for ((i=1; i<$#; i++)); do 
        case "${!i}" in 
            debug|release|develop) rsync_nvsrc_config=${!i} ;;
            branch=*)  rsync_nvsrc_branch="${!i#branch=}" ;;
            version=*) rsync_nvsrc_version="${!i#version=}" ;;
        esac 
    done  
    if [[ -z $rsync_nvsrc_arch ]]; then 
        rsync_nvsrc_arch=$(uname -m | sed 's/x86_64/amd64/g')
    fi 
    if [[ -z $rsync_nvsrc_config ]]; then 
        rsync_nvsrc_config=develop 
    fi 
    if [[ -z $rsync_nvsrc_version ]]; then 
        dso_glcore=$(ldconfig -p | awk '/libnvidia-glcore\.so/{print $NF; exit}')
        dso_glcore=$(basename $(readlink -f $dso_glcore))
        rsync_nvsrc_version=${dso_glcore#libnvidia-glcore.so.}
    fi 
    if [[ -z $rsync_nvsrc_branch || -z $rsync_nvsrc_version ]]; then 
        return 1
    fi 
}

rsync_recv_umd_per_dso() {
    pushd $rsync_dst >/dev/null || return 1
    dso_dir="$rsync_host:/home/wanliz/sw/branch/$rsync_nvsrc_branch/drivers/$1/_out/Linux_${rsync_nvsrc_arch}_${rsync_nvsrc_config}"
    dso_name=$2 
    rsync -Pah $dso_dir/$dso_name $dso_name.$rsync_nvsrc_version || return 1
    ln -sf $dso_name.$rsync_nvsrc_version $dso_name

    find /usr/lib/$(uname -m)-linux-gnu -xdev \( -type f -o -type l \) \( -name $dso_name -o -name $dso_name.* \) -print 2>/dev/null | sort -u | while IFS= read -r dso_path; do 
        basename=${dso_path##*/}
        suffix=${basename#"$dso_name"}
        suffix=${suffix#.}
        if [[ $suffix != $rsync_nvsrc_version ]]; then 
            ln -sf $dso_name.$rsync_nvsrc_version $dso_name.$suffix 
        fi 
    done 
    popd >/dev/null 
}

rsync_recv_umd() {
    rsync_host_io $@ || return 1 
    rsync_nvsrc_io $@ || return 1
    rsync_dst=$HOME/NVIDIA-Linux-UMD-override-$rsync_nvsrc_version
    mkdir -p $rsync_dst
    rsync_recv_umd_per_dso OpenGL libnvidia-glcore.so || return 1
    rsync_recv_umd_per_dso OpenGL/win/egl/build libnvidia-eglcore.so || return 1
    rsync_recv_umd_per_dso OpenGL/win/egl/glsi libnvidia-glsi.so || return 1 
    rsync_recv_umd_per_dso OpenGL/win/unix/tls/Linux-elf libnvidia-tls.so || return 1
    rsync_recv_umd_per_dso OpenGL/win/glx/lib libGLX_nvidia.so || return 1
    rsync_recv_umd_per_dso khronos/egl/egl libEGL_nvidia.so || return 1
    pushd $(dirname $rsync_dst) >/dev/null || return 1
        ln -sf $(basename $rsync_dst) NVIDIA-Linux-UMD-override
    popd >/dev/null 
    pushd $rsync_dst >/dev/null || return 1
        sys_icd_file=$(find /etc/vulkan /usr/share/vulkan /usr/local/share/vulkan -path '*/icd.d/*nvidia*icd*.json' -type f -print 2>/dev/null | head -1)
        if [[ -f $sys_icd_file ]]; then  
            cp -f $sys_icd_file .
            sed -i "s|libGLX_nvidia\.so\.0|$rsync_dst/libGLX_nvidia.so.0|g" nvidia_icd.json
            echo "LD_LIBRARY_PATH=$rsync_dst VK_ICD_FILENAMES=$rsync_dst/nvidia_icd.json" > README.md
        else 
            return 1
        fi 
    popd >/dev/null 
}

rsync_recv_drvpkg() {
    rsync_host_io $@ || return 1 
    rsync_nvsrc_io $@ || return 1
    rsync -Pah $rsync_host:/home/wanliz/sw/branch/$rsync_nvsrc_branch/_out/Linux_${rsync_nvsrc_arch}_${rsync_nvsrc_config}/NVIDIA-Linux-$(uname -m)-$rsync_nvsrc_version-internal.run $HOME/NVIDIA-Linux-$(uname -m)-$rsync_nvsrc_version-$rsync_nvsrc_config.run || return 1
    rsync -Pah $rsync_host:/home/wanliz/sw/branch/$rsync_nvsrc_branch/_out/Linux_${rsync_nvsrc_arch}_${rsync_nvsrc_config}/tests-Linux-$(uname -m).tar $HOME/tests-Linux-$(uname -m)-$rsync_nvsrc_version-$rsync_nvsrc_config.tar 2>/dev/null || true 
}

subcmd_recv() {
    rsync_host_io $@ || return 1 
    case $1 in 
        vb|vulkanbench) shift; rsync_recv_vulkanbench $@ ;;
        umd) shift; rsync_recv_umd $@ ;;
        drvpkg) shift; rsync_recv_drvpkg $@ ;;
        *) rsync -Pah $rsync_host:$1 . ;;
    esac
}

remove_nvidia_module() {
    if [[ -z $(lsmod | grep -E '^nvidia') ]]; then 
        return 0
    fi 
    if [[ ! -z $(which remove-nvidia-module) ]]; then 
        remove-nvidia-module 
    else
        echo "Failed to find remove-nvidia-module in \$PATH" 
    fi 
}

download_nvidia_driver_version() {
    [[ -z $(which wget) ]] && sudo apt install -y wget
    rm -f  $HOME/NVIDIA-Linux-$(uname -m)-$1-release.run
    rm -f  $HOME/tests-Linux-$(uname -m)-$1-release.tar
    rm -rf $HOME/tests-Linux-$(uname -m)-$1-release 
    echo "Downloading ~/NVIDIA-Linux-$(uname -m)-$1-release.run ..."

    version_folder=http://linuxqa/builds/release/display/$(uname -m)/$1
    if wget -S --spider $version_folder; then 
        wget -O $HOME/NVIDIA-Linux-$(uname -m)-$1-release.run http://linuxqa/builds/release/display/$(uname -m)/$1/NVIDIA-Linux-$(uname -m)-$1.run || return 1 
        wget -O $HOME/tests-Linux-$(uname -m)-$1-release.tar http://linuxqa/builds/release/display/$(uname -m)/$1/tests-Linux-$(uname -m).tar || true 
    else
        echo "http://linuxqa/builds/release/display/$(uname -m)/$1 is not reachable"
        if [[ -d /mnt/builds/release ]]; then 
            echo "Retry with /mnt/builds"
            rsync -Pah /mnt/builds/release/display/$(uname -m)/$1/NVIDIA-Linux-$(uname -m)-$1.run $HOME/NVIDIA-Linux-$(uname -m)-$1-release.run || return 1
            rsync -Pah /mnt/builds/release/display/$(uname -m)/$1/tests-Linux-$(uname -m).tar $HOME/tests-Linux-$(uname -m)-$1-release.tar || return 1
        else
            return 1
        fi 
    fi 
}

install_nvidia_driver() {
    if [[ -e $1 ]]; then 
        nvpkg=$1; shift 
        forced_args=
        if [[ -f /.dockerenv || -f /run/.containerenv ]]; then
            forced_args+=" --no-kernel-modules"
        fi 

        no_kernel_modules=
        for arg in $@ $forced_args; do 
            if [[ $arg == "--no-kernel-modules" ]]; then 
                no_kernel_modules=1
            fi 
        done 
        if [[ -z $no_kernel_modules ]]; then 
            remove_nvidia_module || return 1
        fi 
        chmod +x $nvpkg 2>/dev/null 
        sudo $nvpkg $@ $forced_args || return 1
        echo "Driver installed!"
        tests_tarball=${nvpkg/NVIDIA/tests}
        tests_tarball=${tests_tarball/%.run/.tar}
        if [[ -e $tests_tarball ]]; then 
            pushd $(dirname $tests_tarball) >/dev/null 
            tarball_name_stem=${tests_tarball##*/}
            tarball_name_stem=${tarball_name_stem%.tar}
            rm -rf tests-Linux-$(uname -m)
            tar -xf $tests_tarball 
            mv tests-Linux-$(uname -m) $tarball_name_stem
            echo "Driver tests dir: $tarball_name_stem"
            popd >/dev/null 
        fi 
    else
        version=$1; shift 
        if download_nvidia_driver_version $version; then 
            install_nvidia_driver $HOME/NVIDIA-Linux-$(uname -m)-$version-release.run $@
        else 
            sudo /mnt/linuxqa/nvt.sh drivers $version $@ || return 1
        fi 
    fi 
}

subcmd_driver() {
    case $1 in 
        remod) shift; remove_nvidia_module $@ ;;
        install) shift; install_nvidia_driver $@ ;;
        download) shift; download_nvidia_driver_version $@ ;;
    esac
}

subcmd_docker() {
    nvidia_device_nodes() {
        for device_node in \
            /dev/nvidiactl \
            /dev/nvidia-modeset \
            /dev/nvidia-uvm \
            /dev/nvidia-uvm-tools \
            /dev/nvidia[0-9]* \
            /dev/nvidia-caps/nvidia-cap* \
            /dev/nvidia-caps-imex-channels/channel* \
            /dev/dri/renderD* \
            /dev/dri/card*; do
            if [[ -e $device_node ]]; then 
                echo "--device=$device_node "
            fi 
        done
    }

    read -r -s -p "Decode Password: " passwd && echo 
    echo "$passwd" > /tmp/decode_password 

    if ! docker image inspect ubuntu:24.04 &>/dev/null; then 
        docker pull ubuntu:24.04
    fi 

    if [[ $1 == nvl ]]; then 
        docker rm -f wanliz-ubuntu-24.04-nvl &>/dev/null || true 
        docker run -it \
            --name="wanliz-ubuntu-24.04-nvl" \
            --cpuset-cpus=0-71 \
            --cpuset-mems=0 \
            --runtime=runc $(nvidia_device_nodes) \
            -v $HOME/wanliz/bin/config-new-machine.sh:/tmp/config.sh:ro \
            -v /tmp/decode_password:/tmp/decode_password:ro \
            -e TZ=America/Los_Angeles \
            ubuntu:24.04 bash -lic '/tmp/config.sh; exec bash -li'
    elif [[ $1 == galaxy ]]; then 
        docker rm -f wanliz-ubuntu-24.04-galaxy &>/dev/null || true 
        docker run -it \
            --name="wanliz-ubuntu-24.04-galaxy" \
            --cpuset-cpus=0-71 \
            --cpuset-mems=0 \
            --runtime=runc $(nvidia_device_nodes) \
            -v $HOME/wanliz/bin/config-new-machine.sh:/tmp/config.sh:ro \
            -v /tmp/decode_password:/tmp/decode_password:ro \
            -e TZ=America/Los_Angeles \
            -e __GL_DeviceModalityPreference=1 \
            ubuntu:24.04 bash -lic '/tmp/config.sh; exec bash -li' 
    elif [[ $1 == ? ]]; then 
        docker ps -a --filter "name=^wanliz-" --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}\t{{.CreatedAt}}'
    else
        docker rm -f wanliz-ubuntu-24.04 &>/dev/null || true 
        docker run -it \
            --name="wanliz-ubuntu-24.04" \
            --runtime=runc $(nvidia_device_nodes) \
            -v $HOME/wanliz/bin/config-new-machine.sh:/tmp/config.sh:ro \
            -v /tmp/decode_password:/tmp/decode_password:ro \
            -e TZ=America/Los_Angeles \
            ubuntu:24.04 bash -lic '/tmp/config.sh; exec bash -li'
    fi 
}

case $1 in 
    wsl2backup) shift; subcmd_backup_wsl2_home ;;
    pl)  shift; subcmd_wanliz_git pull $@ ;;
    ps)  shift; subcmd_wanliz_git push $@ ;;
    ip)  shift; subcmd_ip $@ ;;
    sw)  shift; subcmd_sw $@ ;;
    env) shift; subcmd_env $@ ;;
    encrypt) shift; subcmd_encrypt "$1" ;;
    decrypt) shift; subcmd_decrypt "$1" ;;
    send) shift; subcmd_send $@ ;;
    recv) shift; subcmd_recv $@ ;;
    driver) shift; subcmd_driver $@ ;;
    docker) shift; subcmd_docker $@ ;;
esac 