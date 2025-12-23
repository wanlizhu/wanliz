#!/usr/bin/env bash
trap 'exit 130' INT


read -p "Do you have sudo access? [Yes/no]: " sudo_access
if [[ -z $sudo_access || $sudo_access =~ ^([yY]([eE][sS])?)?$ ]]; then 
    sudo_access=yes
else
    sudo_access=
fi 

if [[ $sudo_access == yes && $EUID != 0 ]]; then 
    if ! sudo grep -qxF "$USER ALL=(ALL) NOPASSWD:ALL" /etc/sudoers; then 
        read -p "Enable no-password sudo for $USER? [Yes/no]: " nopasswd_sudo 
        if [[ -z $nopasswd_sudo || $nopasswd_sudo =~ ^([yY]([eE][sS])?)?$ ]]; then 
            echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee -a /etc/sudoers &>/dev/null
        fi 
    fi
fi 

if [[ $sudo_access == yes ]]; then 
    if grep -q "# wanliz" /etc/hosts; then 
        read -p "Reconfigure /etc/hosts? [Yes/no]: " add_hosts
    else 
        read -p "Configure /etc/hosts? [Yes/no]: " add_hosts
    fi 
    if [[ -z $add_hosts || $add_hosts =~ ^([yY]([eE][sS])?)?$ ]]; then 
        sudo sed -i '\|# wanliz|d' /etc/hosts
        sudo tee -a /etc/hosts >/dev/null <<'EOF'
172.16.179.143 office       # wanliz
172.16.178.123 horizon5     # wanliz 
172.16.177.182 horizon6     # wanliz 
172.16.177.216 horizon7     # wanliz 
10.31.86.235   nvtest-spark nvtest-172          # wanliz 
10.176.11.106  nvtest-0110  4u2g-0110           # wanliz 
10.178.94.106  nvtest-gb300   nvtest-galaxy     # wanliz 
10.176.195.179 nvtest-gb300-2 nvtest-galaxy-2   # wanliz 
EOF
    fi 
fi 

if [[ -f $HOME/.ssh/config  ]]; then 
    read -p "Reconfigure (override) ~/.ssh/config? [Yes/no]: " ssh_config
else 
    read -p "Configure ~/.ssh/config? [Yes/no]: " ssh_config
fi 
if [[ -z $ssh_config || $ssh_config =~ ^([yY]([eE][sS])?)?$ ]]; then 
    mkdir -p $HOME/.ssh 
    tee $HOME/.ssh/config >/dev/null <<'EOF'
Host xterm                             
    HostName dc2-container-xterm-028.prd.it.nvidia.com   
    User wanliz                         
    Port 4483                          
    IdentityFile ~/.ssh/id_ed25519      
    IdentitiesOnly no                  

Host gb300-cluster                      
    HostName cls-pdx-ipp6-bcm-3         
    User wanliz                     
    IdentityFile ~/.ssh/id_ed25519      
    IdentitiesOnly no                   

Host gb300-with-sudo                     
    HostName gb300-nvl-022-compute03     
    User dlfwadmin                      
    IdentityFile ~/.ssh/id_ed25519      
    IdentitiesOnly no                   
EOF
fi 

if [[ ! -f $HOME/.ssh/id_ed25519 ]]; then 
    read -p "Restore wanliz's SSH ID from xterm? [Yes/no]: " ssh_id
    if [[ -z $ssh_id || $ssh_id =~ ^([yY]([eE][sS])?)?$ ]]; then 
        mkdir -p $HOME/.ssh 
        rsync -ah --progress wanliz@xterm:/home/wanliz/.ssh/id_ed25519     $HOME/.ssh/id_ed25519
        rsync -ah --progress wanliz@xterm:/home/wanliz/.ssh/id_ed25519.pub $HOME/.ssh/id_ed25519.pub
        # SSH may refuse keys without correct permission
        chmod 700 $HOME/.ssh 
        chmod 600 $HOME/.ssh/id_ed25519
        chmod 644 $HOME/.ssh/id_ed25519.pub 
    fi 
fi 

if [[ $sudo_access == yes ]]; then 
    read -p "Install profiling packages? [Yes/no]: " install_pkg 
    if [[ -z $install_pkg || $install_pkg =~ ^([yY]([eE][sS])?)?$ ]]; then 
        python_version=$(python3 -c 'import sys; print(f"{sys.version_info[0]}.{sys.version_info[1]}")')
        for pkg in python${python_version}-dev python${python_version}-venv \
            python3-pip python3-protobuf protobuf-compiler \
            libxcb-dri2-0 nis autofs jq rsync vim curl screen sshpass \
            lsof x11-xserver-utils x11-utils openbox obconf x11vnc \
            mesa-utils vulkan-tools xserver-xorg-core \
            samba samba-common-bin socat cmake build-essential \
            ninja-build pkg-config libjpeg-dev smbclient 
        do 
            if ! dpkg -s $pkg &>/dev/null; then
                echo -n "Installing $pkg ... "
                sudo apt install -y $pkg &>/dev/null && echo "[OK]" || echo "[FAILED]"
            fi 
        done 
    fi 
fi 

read -p "Install profiling scripts? [Yes/no]: " install_symlinks 
if [[ -z $install_symlinks || $install_symlinks =~ ^([yY]([eE][sS])?)?$ ]]; then 
    mkdir -p $HOME/.local/bin
    read -e -i $(dirname $(readlink -f $0)) -p "Create symlinks to scripts in: " scripts_dir
    find $HOME/.local/bin -maxdepth 1 -type l -print0 | while IFS= read -r -d '' link; do 
        if real_target=$(readlink -f "$link"); then  
            if [[ $real_target == *"/wanliz/"* ]]; then 
                rm -f "$link" &>/dev/null 
            fi 
        else
            rm -f "$link" &>/dev/null 
        fi 
    done 
    for file in $scripts_dir/*.*; do 
        [[ -f $file && -x $file ]] || continue 
        cmdname=$(basename "$file")
        cmdname=${cmdname%.sh}
        cmdname=${cmdname%.py}
        ln -sf $file $HOME/.local/bin/$cmdname &>/dev/null 
    done 
fi 

if [[ -f $HOME/.vimrc ]]; then 
    read -p "Reconfigure (override) ~/.vimrc? [Yes/no]: " config_vimrc
else 
    read -p "Configure ~/.vimrc? [Yes/no]: " config_vimrc
fi 
if [[ -z $config_vimrc || $config_vimrc =~ ^([yY]([eE][sS])?)?$ ]]; then 
    cat > $HOME/.vimrc <<'EOF'
set expandtab        
set tabstop=4        
set shiftwidth=4     
set softtabstop=4    
EOF
fi 

if [[ -f $HOME/.screenrc ]]; then 
    read -p "Reconfigure (override) ~/.screenrc? [Yes/no]: " config_screenrc
else 
    read -p "Configure ~/.screenrc? [Yes/no]: " config_screenrc
fi 
if [[ -z $config_screenrc || $config_screenrc =~ ^([yY]([eE][sS])?)?$ ]]; then 
    cat > $HOME/.screenrc <<'EOF' 
startup_message off     
hardstatus alwaysfirstline 
hardstatus string '%{= bW} [SCREEN %S]%{= bW} win:%n:%t %=%-Lw%{= kW}%n:%t%{-}%+Lw %=%Y-%m-%d %c:%s '
EOF
fi 

if [[ $sudo_access == yes ]]; then 
    if [[ ! -d /mnt/linuxqa/wanliz ]]; then 
        # mounting corporate NFS directly from WSL is not supported reliably. 
        # It works on a real Linux host on the same network, 
        # but WSL lacks the kernel RPC plumbing NFS expects, 
        # even when basic TCP connectivity exists.
        if [[ -d /mnt/c/Users/ ]]; then 
            # Mount NFS folder
            # mount.exe linuxqa.nvidia.com:/storage/people Z:
            # Mount SMB folder
            # \\linuxqa\people (login with wanliz@nvidia.com)
            echo >/dev/null 
        else 
            read -p "Mount /mnt/linuxqa? [Yes/no]: " mount_linuxqa 
            if [[ -z $mount_linuxqa || $mount_linuxqa =~ ^([yY]([eE][sS])?)?$ ]]; then 
                echo -n "Mounting /mnt/linuxqa ... "
                if [[ ! -d /mnt/linuxqa ]]; then 
                    sudo mkdir -p /mnt/linuxqa 
                fi 
                sudo mount -t nfs linuxqa.nvidia.com:/storage/people /mnt/linuxqa || echo "Failed to mount /mnt/linuxqa"
            fi 
        fi 
    fi 
fi 

echo "All done!"
