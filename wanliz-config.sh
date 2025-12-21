#!/usr/bin/env bash
trap 'exit 130' INT

YES_FOR_ALL=
if [[ $1 == -y ]]; then 
    YES_FOR_ALL=1
fi 

if [[ $EUID != 0 ]]; then 
    [[ -z $YES_FOR_ALL ]] && read -p "Set up no-password sudo for $USER? [Y/n]: " nopasswd_sudo || nopasswd_sudo=
    if [[ -z $nopasswd_sudo || $nopasswd_sudo =~ ^([yY]([eE][sS])?)?$ ]]; then 
        if ! sudo grep -qxF "$USER ALL=(ALL) NOPASSWD:ALL" /etc/sudoers; then 
            echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee -a /etc/sudoers &>/dev/null
            echo "[OK]"
        else
            echo "[SKIPPED]"
        fi
    fi 
fi 

if ! grep -q "wanliz utils hosts" /etc/hosts; then 
    read -p "Add hosts to /etc/hosts? [Y/n]: " add_hosts
    if [[ -z $add_hosts || $add_hosts =~ ^([yY]([eE][sS])?)?$ ]]; then 
        echo -e "\n# wanliz utils hosts" | sudo tee -a /etc/hosts >/dev/null 
        cat $HOME/wanliz/hosts.txt | sudo tee -a /etc/hosts >/dev/null 
    fi 
fi 

if [[ ! -f $HOME/.ssh/config  ]]; then 
    read -p "Add configs to ~/.ssh/config? [Y/n]: " ssh_config
    mkdir -p $HOME/.ssh 
    if [[ -z $ssh_config || $ssh_config =~ ^([yY]([eE][sS])?)?$ ]]; then 
        echo >> $HOME/.ssh/config
        cat $HOME/wanliz/ssh-config.txt >> $HOME/.ssh/config
    fi 
fi 

if [[ ! -f $HOME/.ssh/id_ed25519 ]]; then 
    read -p "Restore wanliz's SSH ID? [Y/n]: " ssh_id
    if [[ -z $ssh_id || $ssh_id =~ ^([yY]([eE][sS])?)?$ ]]; then 
        mkdir -p $HOME/.ssh 
        rsync -ah wanliz@office:/home/wanliz/.ssh/id_ed25519     $HOME/.ssh/id_ed25519
        rsync -ah wanliz@office:/home/wanliz/.ssh/id_ed25519.pub $HOME/.ssh/id_ed25519.pub
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
fi 

if [[ $USER == wanliz ]]; then 
    [[ -z $YES_FOR_ALL ]] && read -p "Set up global git options? [Y/n]: " setup_git || setup_git=
    if [[ -z $setup_git || $setup_git =~ ^([yY]([eE][sS])?)?$ ]]; then 
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
            sudo mount -t nfs linuxqa.nvidia.com:/storage/people /mnt/linuxqa && echo "[OK]" || {
                echo "[FAILED] - rerun for debug info"
                timeout 1s sudo mount -vvv -t nfs linuxqa.nvidia.com:/storage/people /mnt/linuxqa 
                sudo dmesg | tail -10
            }
        fi 
    fi 
fi 

echo "All done!"
