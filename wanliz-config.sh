#!/usr/bin/env bash
trap 'exit 130' INT

YES_FOR_ALL=
if [[ $1 == -y ]]; then 
    YES_FOR_ALL=1
fi 

if [[ $EUID != 0 ]]; then 
    [[ -z $YES_FOR_ALL ]] && read -p "Enable no-password sudo for $USER? [Y/n]: " nopasswd_sudo || nopasswd_sudo=
    if [[ -z $nopasswd_sudo || $nopasswd_sudo =~ ^([yY]([eE][sS])?)?$ ]]; then 
        echo -n "Enabling no-password sudo ... "
        if ! sudo grep -qxF "$USER ALL=(ALL) NOPASSWD:ALL" /etc/sudoers; then 
            echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee -a /etc/sudoers &>/dev/null
            echo "[OK]"
        else
            echo "[SKIPPED]"
        fi
    fi 
fi 

[[ -z $YES_FOR_ALL ]] && read -p "Install profiling packages? [Y/n]: " install_pkg || install_pkg=
if [[ -z $install_pkg || $install_pkg =~ ^([yY]([eE][sS])?)?$ ]]; then 
    python_version=$(python3 -c 'import sys; print(f"{sys.version_info[0]}.{sys.version_info[1]}")')
    for pkg in python${python_version}-dev python${python_version}-venv \
        python3-pip python3-protobuf protobuf-compiler \
        libxcb-dri2-0 nis autofs jq rsync vim curl screen sshpass \
        lsof x11-xserver-utils x11-utils openbox obconf x11vnc \
        mesa-utils vulkan-tools xserver-xorg-core \
        samba samba-common-bin socat cmake build-essential \
        ninja-build pkg-config libjpeg-dev
    do 
        if ! dpkg -s $pkg &>/dev/null; then
            echo -n "Installing $pkg ... "
            sudo apt install -y $pkg &>/dev/null && echo "[OK]" || echo "[FAILED]"
        fi 
    done 

    if [[ ! -z $(which p4v) ]]; then 
        for pkg in libkf5syntaxhighlighting5 \
            libqt6webenginewidgets6 \
            qt6-webengine-dev \
            libqt6svg6 \
            libqt6multimedia6
        do 
            if ! dpkg -s $pkg &>/dev/null; then
                echo -n "Installing $pkg ... "
                sudo apt install -y $pkg &>/dev/null && echo "[OK]" || echo "[FAILED]"
            fi 
        done 
    fi 
fi 

[[ -z $YES_FOR_ALL ]] && read -p "Install symlinks of profiling scripts to /usr/local/bin? [Y/n]: " install_symlinks || install_symlinks=
if [[ -z $install_symlinks || $install_symlinks =~ ^([yY]([eE][sS])?)?$ ]]; then 
    echo -n "Installing wanliz-* scripts to /usr/local/bin ... "
    find /usr/local/bin -maxdepth 1 -type l -print0 | while IFS= read -r -d '' link; do 
        if real_target=$(readlink -f "$link"); then  
            if [[ $real_target == *"/wanliz/"* ]]; then 
                sudo rm -f "$link" &>/dev/null 
            fi 
        else
            sudo rm -f "$link" &>/dev/null 
        fi 
    done 
    for file in $HOME/wanliz/*; do 
        [[ -f "$file" && -x "$file" ]] || continue 
        cmdname=$(basename "$file")
        cmdname="${cmdname%.sh}"
        cmdname="${cmdname%.py}"
        sudo ln -sf "$file" "/usr/local/bin/$cmdname" &>/dev/null 
    done 
    echo "[OK]"
fi 

if [[ $USER == wanliz ]]; then 
    [[ -z $YES_FOR_ALL ]] && read -p "Configure global git options? [Y/n]: " config_git || config_git=
    if [[ -z $config_git || $config_git =~ ^([yY]([eE][sS])?)?$ ]]; then 
        git_email=$(git config --global user.email 2>/dev/null || true)
        if [[ -z $git_email ]]; then
            git config --global user.email "zhu.wanli@icloud.com"
        fi 
        git_name=$(git config --global user.name 2>/dev/null || true)
        if [[ -z $git_name ]]; then
            git config --global user.name "Wanli Zhu"
        fi 
        git_editor=$(git config --global core.editor 2>/dev/null || true)
        if [[ -z $git_editor ]]; then
            if [[ -z $(which vim) ]]; then 
                sudo apt install -y vim 2>/dev/null
            fi 
            git config --global core.editor "vim"
        fi
    fi 
fi 

if [[ $USER == wanliz ]]; then 
    if [[ ! -f ~/.vimrc ]]; then 
        cat <<'EOF' > ~/.vimrc
set expandtab
set tabstop=4
set shiftwidth=4
set softtabstop=4
EOF
    fi 

    if [[ ! -f ~/.screenrc ]]; then
        cat <<'EOF' > ~/.screenrc
caption always "%{= bw}%{+b} %t (%n) | %H | %Y-%m-%d %c | load %l"
hardstatus on
hardstatus alwayslastline "%{= kW}%-w%{= kG}%n*%t%{-}%+w %=%{= ky}%H %{= kw}%Y-%m-%d %c %{= kc}load %l"
EOF
    fi 
fi 

if [[ ! -d /mnt/linuxqa/wanliz && ! -d /mnt/c/Users/ ]]; then 
    [[ -z $YES_FOR_ALL ]] && read -p "Mount /mnt/linuxqa? [Y/n]: " mount_linuxqa || mount_linuxqa=
    if [[ -z $mount_linuxqa || $mount_linuxqa =~ ^([yY]([eE][sS])?)?$ ]]; then 
        echo -n "Mounting /mnt/linuxqa ... "
        if [[ ! -d /mnt/linuxqa ]]; then 
            sudo mkdir -p /mnt/linuxqa 
        fi 
        if mountpoint -q /mnt/linuxqa; then 
            echo "[SKIPPED]"
        else
            timeout 5s sudo mount -t nfs linuxqa.nvidia.com:/storage/people /mnt/linuxqa && echo "[OK]" || {
                echo "[FAILED] - rerun for debug info"
                timeout 1s sudo mount -vvv -t nfs linuxqa.nvidia.com:/storage/people /mnt/linuxqa 
                sudo dmesg | tail -10
            }
        fi 
    fi 
fi 

echo "All done!"
