#!/usr/bin/env bash
trap 'exit 130' INT

read -p "Do you have sudo access? [Yes/no]: " sudo_access
if [[ $sudo_access =~ ^[[:space:]]*([yY]([eE][sS])?)?[[:space:]]*$ ]]; then 
    sudo_access=yes
else
    sudo_access=
fi 

inside_container=
if [[ -f /.dockerenv || -f /run/.containerenv ]]; then
    inside_container=yes 
fi 

booted_with_systemd=
if [[ "$(ps -p 1 -o comm= 2>/dev/null)" == systemd ]]; then
    booted_with_systemd=yes 
fi 

if [[ $sudo_access == yes ]]; then 
    if [[ $booted_with_systemd == yes ]]; then 
        if [[ -e /etc/timezone ]]; then 
            etc_timezone=$(tr -d ' \t\r\n' </etc/timezone 2>/dev/null || true)
            localtime=$(readlink -f /etc/localtime 2>/dev/null || true)
            tz_localtime=""
            if [[ "$localtime" == /usr/share/zoneinfo/* ]]; then  
                tz_localtime="${localtime#/usr/share/zoneinfo/}"
            fi 
            if [[ ! -z "$tz_localtime" && ( -z "$etc_timezone" || "$etc_timezone" != "$tz_localtime" ) ]]; then
                echo "Local timezone: $tz_localtime"
                echo " /etc/timezone: $etc_timezone"
                read -p "Update /etc/timezone? [Yes/no]: " adjust_tz
                if [[ $adjust_tz =~ ^[[:space:]]*([yY]([eE][sS])?)?[[:space:]]*$ ]]; then
                    sudo timedatectl set-timezone "$tz_localtime" 
                    sudo ln -sf "/usr/share/zoneinfo/$tz_localtime" /etc/localtime
                    echo "$tz_localtime" | sudo tee /etc/timezone >/dev/null
                fi 
            fi
        fi 

        timedatectl
        echo "If machine clock is behind, apt refuses to use some repos."
        read -p "Is the local time correct? [Yes/no]: " time_correct
        if [[ $time_correct =~ ^[[:space:]]*([nN]|[nN][oO])[[:space:]]*$ ]]; then 
            read -e -i "$(date '+%F %T')" -p "The correct local time: " corrected_time
            sudo date -s "$corrected_time"
            sudo apt update &>/dev/null 
        fi 
    fi 
fi 

if [[ $sudo_access == yes && $EUID != 0 ]]; then 
    if ! sudo grep -qxF "$USER ALL=(ALL) NOPASSWD:ALL" /etc/sudoers; then 
        read -p "Enable passwordless sudo for $USER? [Yes/no]: " passwordless_sudo 
        if [[ $passwordless_sudo =~ ^[[:space:]]*([yY]([eE][sS])?)?[[:space:]]*$ ]]; then
            echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee -a /etc/sudoers &>/dev/null
        fi 
    fi
fi 

if [[ -d /mnt/c/Users/ || $inside_container == yes ]]; then 
    download_bashrc=no
else 
    if [[ ! -f $HOME/.bashrc_wsl2 ]]; then 
        read -p "Download ~/.bashrc_wsl2 from remote workspace? [Yes/no]: " download_bashrc
    else
        read -p "Download ~/.bashrc_wsl2 (override) from remote workspace? [Yes/no]: " download_bashrc
    fi 
fi 
if [[ $download_bashrc =~ ^[[:space:]]*([yY]([eE][sS])?)?[[:space:]]*$ ]]; then
    if [[ -f $HOME/.bashrc_wsl2_ip ]]; then 
        if ! sudo ping -c 1 -W 3 "$(cat $HOME/.bashrc_wsl2_ip 2>/dev/null)"; then 
            sudo rm -f $HOME/.bashrc_wsl2_ip
        fi  
    fi 
    if [[ ! -f $HOME/.bashrc_wsl2_ip ]]; then 
        read -p "Remote server IP: " remote_ip
        echo "$remote_ip" > $HOME/.bashrc_wsl2_ip
    fi 
    remote_ip=$(cat $HOME/.bashrc_wsl2_ip)

    if ! ssh -o BatchMode=yes -o PreferredAuthentications=publickey -o PasswordAuthentication=no -o ConnectTimeout=5 wanliz@$remote_ip 'true' &>/dev/null; then 
        if [[ ! -f $HOME/.ssh/id_ed25519  ]]; then 
            ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519
        fi 
        ssh-copy-id wanliz@$remote_ip
    fi 

    rsync -ah --progress wanliz@$remote_ip:/home/wanliz/.bashrc $HOME/.bashrc_wsl2 && {
        awk -v m='# wanliz env vars' 'found {print} $0==m {found=1; print}' $HOME/.bashrc_wsl2 >/tmp/bashrc_wsl2 &&
        mv -f /tmp/bashrc_wsl2 $HOME/.bashrc_wsl2 &&
        echo "Downloaded $HOME/.bashrc_wsl2"
    } || echo "Failed to download ~/.bashrc_wsl2 from $remote_ip"
fi 

if [[ $inside_container == yes ]]; then 
    ssh_config=no
else 
    if [[ -f $HOME/.ssh/config  ]]; then 
        read -p "Reconfigure (override) ~/.ssh/config? [Yes/no]: " ssh_config
    else 
        read -p "Configure ~/.ssh/config? [Yes/no]: " ssh_config
    fi 
fi 
if [[ $ssh_config =~ ^[[:space:]]*([yY]([eE][sS])?)?[[:space:]]*$ ]]; then
    mkdir -p $HOME/.ssh 
    tee $HOME/.ssh/config >/dev/null <<'EOF'
Host *
    StrictHostKeyChecking accept-new
    UserKnownHostsFile /dev/null

Host xterm                             
    HostName dc2-container-xterm-028.prd.it.nvidia.com   
    User wanliz                         
    Port 4483                          
    IdentityFile ~/.ssh/id_ed25519      

Host office                             
    HostName 172.16.179.143
    User wanliz                           
    IdentityFile ~/.ssh/id_ed25519            

Host gb300-compute-cluster                      
    HostName cls-pdx-ipp6-bcm-3         
    User wanliz                     
    IdentityFile ~/.ssh/id_ed25519      

Host nvtest-spark-proxy
    HostName 10.176.11.106
    User nvidia
    IdentityFile ~/.ssh/id_ed25519 

Host nvtest-spark-172
    HostName 10.31.86.235
    User nvidia
    IdentityFile ~/.ssh/id_ed25519 

Host nvtest-galaxy-015
    HostName 10.178.94.106  
    User nvidia
    IdentityFile ~/.ssh/id_ed25519

Host nvtest-galaxy-048
    HostName 10.176.195.179
    User nvidia
    IdentityFile ~/.ssh/id_ed25519
EOF
fi 

if [[ $inside_container == yes ]]; then 
    config_vimrc=no
else 
    if [[ -f $HOME/.vimrc ]]; then 
        read -p "Reconfigure (override) ~/.vimrc? [Yes/no]: " config_vimrc
    else 
        read -p "Configure ~/.vimrc? [Yes/no]: " config_vimrc
    fi 
fi 
if [[ $config_vimrc =~ ^[[:space:]]*([yY]([eE][sS])?)?[[:space:]]*$ ]]; then
    cat > $HOME/.vimrc <<'EOF'
set expandtab        
set tabstop=4        
set shiftwidth=4     
set softtabstop=4    
EOF
fi 

if [[ $inside_container == yes ]]; then 
    config_screenrc=no
else 
    if [[ -f $HOME/.screenrc ]]; then 
        read -p "Reconfigure (override) ~/.screenrc? [Yes/no]: " config_screenrc
    else 
        read -p "Configure ~/.screenrc? [Yes/no]: " config_screenrc
    fi 
fi 
if [[ $config_screenrc =~ ^[[:space:]]*([yY]([eE][sS])?)?[[:space:]]*$ ]]; then
    cat > $HOME/.screenrc <<'EOF' 
startup_message off     
hardstatus alwaysfirstline 
hardstatus string '%{= bW} [SCREEN %S]%{= bW} win:%n:%t %=%-Lw%{= kW}%n:%t%{-}%+Lw %=%Y-%m-%d %c:%s '
EOF
fi 

if [[ $sudo_access == yes ]]; then 
    read -p "Install profiling packages? [Yes/no]: " install_pkg 
    if [[ $install_pkg =~ ^[[:space:]]*([yY]([eE][sS])?)?[[:space:]]*$ ]]; then
        if [[ -z $(which python3) ]]; then 
            sudo apt install -y python3 &>/dev/null 
        fi 

        python_version=$(python3 -c 'import sys; print(f"{sys.version_info[0]}.{sys.version_info[1]}")')
        for pkg in python${python_version}-dev python${python_version}-venv \
            python3-pip python3-protobuf protobuf-compiler \
            libxcb-dri2-0 nis autofs jq rsync vim curl screen sshpass \
            lsof x11-xserver-utils x11-utils openbox obconf x11vnc \
            mesa-utils vulkan-tools xserver-xorg-core \
            samba samba-common-bin socat cmake build-essential \
            ninja-build pkg-config libjpeg-dev smbclient \
            libboost-program-options-dev 
        do 
            if ! dpkg -s $pkg &>/dev/null; then
                echo -n "Installing $pkg ... "
                sudo apt install -y $pkg &>/dev/null && echo "[OK]" || echo "[FAILED]"
            fi 
        done 

        if [[ -d $HOME/SinglePassCapture ]]; then 
            python3 -m pip install --break-system-packages -r $HOME/SinglePassCapture/Scripts/requirements.txt &>/dev/null 
        fi 
    fi 
fi 

read -p "Install profiling scripts? [Yes/no]: " install_symlinks 
if [[ $install_symlinks =~ ^[[:space:]]*([yY]([eE][sS])?)?[[:space:]]*$ ]]; then
    mkdir -p $HOME/.local/bin
    if [[ -d /home/wanliz/wanliz ]]; then 
        read -e -i $HOME/wanliz -p "Confirm scripts folder: " scripts_dir
    else
        read -p "Set scripts folder: " scripts_dir
    fi 

    if [[ -d $scripts_dir ]]; then 
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
fi 

if [[ $sudo_access == yes ]]; then 
    if [[ ! -d /mnt/linuxqa/wanliz ]]; then 
        # mounting corporate NFS directly from WSL is not supported reliably. 
        # It works on a real Linux host on the same network, 
        # but WSL lacks the kernel RPC plumbing NFS expects, 
        # even when basic TCP connectivity exists.
        if [[ -d /mnt/c/Users/ || $inside_container == yes ]]; then 
            # Mount NFS folder
            # mount.exe linuxqa.nvidia.com:/storage/people Z:
            # Mount SMB folder
            # \\linuxqa\people (login with wanliz@nvidia.com)
            echo "NFS mounting is not supported, skipped!" 
        else 
            read -p "Mount /mnt/linuxqa? [Yes/no]: " mount_linuxqa 
            if [[ $mount_linuxqa =~ ^[[:space:]]*([yY]([eE][sS])?)?[[:space:]]*$ ]]; then
                echo -n "Mounting /mnt/linuxqa ... "
                sudo mkdir -p /mnt/linuxqa &&
                sudo mount -t nfs linuxqa.nvidia.com:/storage/people /mnt/linuxqa || echo "Failed to mount /mnt/linuxqa"
            fi 
        fi 
    fi 
    # findmnt -o TARGET,SOURCE,FSTYPE,OPTIONS
fi 

echo "All done!"
