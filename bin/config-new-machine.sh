#!/usr/bin/env bash
trap 'exit 130' INT

if [[ -z $(echo "$PATH" | grep "$HOME/bin") ]]; then 
    echo "" >> $HOME/.bashrc
    echo 'export PATH="$HOME/bin:$PATH"' >> $HOME/.bashrc 
fi 

if [[ -z $(grep "subcmd_env" $HOME/.bashrc) ]]; then 
    {
        echo ""
        echo "if [[ -e \$HOME/bin/zhu ]]; then" 
        echo "    source \$HOME/bin/zhu" 
        echo "    subcmd_env"
        echo "fi"
    } >> $HOME/.bashrc 
fi 

read -p "Do you have sudo access? [Yes/no]: " sudo_access
if [[ $sudo_access =~ ^[[:space:]]*([yY]([eE][sS])?)?[[:space:]]*$ ]]; then 
    sudo_access=yes
else
    sudo_access=
fi 

inside_container=
if [[ -f /.dockerenv || -f /run/.containerenv ]]; then
    inside_container=yes 
    echo "Verbose mode forced to enabled inside container"
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
            sudo apt update 
        fi 
    fi 
fi 

if [[ $sudo_access == yes && $EUID != 0 ]]; then 
    if ! sudo grep -qxF "$USER ALL=(ALL) NOPASSWD:ALL" /etc/sudoers; then 
        read -p "Enable passwordless sudo for $USER? [Yes/no]: " passwordless_sudo 
        if [[ $passwordless_sudo =~ ^[[:space:]]*([yY]([eE][sS])?)?[[:space:]]*$ ]]; then
            echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee -a /etc/sudoers
        fi 
    fi
fi 

if [[ -z $sudo_access || $inside_container == yes ]]; then 
    ssh_config=no
else 
    read -p "Check and update ~/.ssh/config? [Yes/no]: " ssh_config
fi 
if [[ $ssh_config =~ ^[[:space:]]*([yY]([eE][sS])?)?[[:space:]]*$ ]]; then
    mkdir -p $HOME/.ssh 
    touch $HOME/.ssh/config
    if ! grep -qE '^[[:space:]]*Host[[:space:]]+\*[[:space:]]*$' $HOME/.ssh/config; then 
        {
            echo ""
            echo "Host *"
            echo "    StrictHostKeyChecking accept-new"
            echo "    UserKnownHostsFile /dev/null"
        } >> $HOME/.ssh/config
    fi 

    known_host_names=(
        "xterm dc2-container-xterm-028.prd.it.nvidia.com 4483 wanliz" 
        "office 172.16.179.143 22 wanliz" 
        "gb300-compute-cluster cls-pdx-ipp6-bcm-3 22 wanliz"
        "nvtest-spark 10.31.86.235 22 nvidia"
        "nvtest-spark-proxy 10.176.11.106 22 nvidia"
        "nvtest-galaxy-015 10.178.94.106 22 nvidia"
        "nvtest-galaxy-048 10.176.195.179 22 nvidia"
    )
    for line in "${known_host_names[@]}"; do 
        read -r name host port user <<< "$line"
        if ! grep -qE "^[[:space:]]*Host[[:space:]]+$name"'([[:space:]]|$)' $HOME/.ssh/config; then 
            {
                echo ""
                echo "Host $name"
                echo "    HostName $host"
                echo "    Port $port"
                echo "    User $user"
                echo "    IdentityFile ~/.ssh/id_ed25519"
            } >> $HOME/.ssh/config
        fi 
    done 
fi 

if [[ ! -f $HOME/.ssh/id_ed25519 ]]; then 
    read -p "Restore ~/.ssh/id_ed25519 ? [Yes/no]: " restore_sshkey
    if [[ $restore_sshkey =~ ^[[:space:]]*([yY]([eE][sS])?)?[[:space:]]*$ ]]; then
        read -r -s -p "Password: " passwd
        mkdir -p $HOME/.ssh 
        echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHx7hz8+bJjBioa3Rlvmaib8pMSd0XTmRwXwaxrT3hFL' > $HOME/.ssh/id_ed25519.pub
        echo 'U2FsdGVkX194Pw+9XfMd3nfRt4STW9D9T2Cfbfjyf9IOwLQ+LsX9oxjoMif8igzU
hWs5GORzVsIwnhVb4W2AktmEWiLNxdCSsOG9Ilztf91kKo0LFtaEIU6H+UF5+mrL
YByA0uXa+GDRUtLDbZbHgOKxQyWWj9yZ+Pyr/nsMM0HzcJLC3T+9NfJaBoL5416a
wCtoEJhZk8LqXS79GLACgfclhU8uhAuIQjglmMZfiOLIJY+KttbI0kVDpdnDwMLJ
UovXaoJ9gcfGlJNwuCENUAyhRuPdWrdvm42GRNwUlJKzaJ8Dvzs6x+EABz5n+x1o
myN2A0GssInc0y4UMUlNjZysTCU8uba0K7rN2F163gRmLk+8dVOhDSV4zp63j1Dv
H+0JYROsG3k1svGml1Mmkz2Xkw22KpGJzeElhSmK1UYtEElVM+/9qYIeg0OBi27I
2egIAOukXs0xiBftt+PJ8fF7QeEn2+p4Tzjjt7qHebfFpoI9WreK5KfYow4TP++l
nDj6vTRTsVlLb+1WffkxHCMVvvjFS9NzEJoZ1DBKFx1yhCoQ5U98eYFemtRfi+Xe' | openssl enc -d -aes-256-cbc -salt -pbkdf2 -a -k $passwd > $HOME/.ssh/id_ed25519
    fi 
fi 

if [[ -z $sudo_access || $inside_container == yes ]]; then 
    config_vimrc=no
else 
    read -p "Check and override ~/.vimrc? [Yes/no]: " config_vimrc
fi 
if [[ $config_vimrc =~ ^[[:space:]]*([yY]([eE][sS])?)?[[:space:]]*$ ]]; then
    {
        echo "set expandtab"        
        echo "set tabstop=4"        
        echo "set shiftwidth=4"     
        echo "set softtabstop=4"    
    } > $HOME/.vimrc
fi 

if [[ -z $sudo_access || $inside_container == yes ]]; then 
    config_screenrc=no
else 
    read -p "Check and override ~/.screenrc? [Yes/no]: " config_screenrc
fi 
if [[ $config_screenrc =~ ^[[:space:]]*([yY]([eE][sS])?)?[[:space:]]*$ ]]; then
    {
        echo "startup_message off"     
        echo "hardstatus alwaysfirstline" 
        echo "hardstatus string %{= bW} [SCREEN %S]%{= bW} win:%n:%t %=%-Lw%{= kW}%n:%t%{-}%+Lw %=%Y-%m-%d %c:%s '"
    } > $HOME/.screenrc
fi 

if [[ $sudo_access == yes ]]; then 
    read -p "Install missing apt packages? [Yes/no]: " install_pkg 
    if [[ $install_pkg =~ ^[[:space:]]*([yY]([eE][sS])?)?[[:space:]]*$ ]]; then
        apt-check-or-install() {
            local missing=()
            for pkg in "$@"; do
                if ! dpkg -s $pkg &>/dev/null; then
                    missing+=($pkg)
                fi
            done
            if ((${#missing[@]} > 0)); then
                sudo apt-get update 
                sudo apt-get install -y ${missing[@]}
                case ${missing[@]} in 
                    openssh-server) sudo systemctl enable --now ssh.service ;;
                esac 
            fi
        }

        apt-check-or-install libxcb-cursor0 libxcb-dri2-0 libjpeg-dev vim git cmake build-essential ninja-build pkg-config clang rsync curl unzip openssh-server sshpass samba samba-common-bin smbclient python3 python3-dev python3-venv python3-pip jq screen mesa-utils vulkan-tools x11vnc net-tools mount.nfs mount.cifs
    fi 
fi 

mkdir -p $HOME/bin 
find $HOME/bin -maxdepth 1 -type l -print0 | while IFS= read -r -d '' link; do 
    if real_target=$(readlink -f "$link"); then  
        if [[ $real_target == *"/wanliz/"* ]]; then 
            rm -f "$link" &>/dev/null
        fi 
    else
        rm -f "$link" &>/dev/null 
    fi 
done 
if [[ -d $HOME/wanliz/bin ]]; then 
    for file in $HOME/wanliz/bin/*.*; do 
        cmdName=$(basename "$file")
        cmdName=${cmdName%.sh}
        cmdName=${cmdName%.py}
        ln -vsf $file $HOME/bin/$cmdName
    done 
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
                echo "Mounting /mnt/linuxqa ... "
                sudo mkdir -p /mnt/linuxqa &&
                sudo mount -t nfs linuxqa.nvidia.com:/storage/people /mnt/linuxqa || echo "Failed to mount /mnt/linuxqa"
            fi 
        fi 
    fi 
    # findmnt -o TARGET,SOURCE,FSTYPE,OPTIONS
fi 

if [[ -d /mnt/c/Users/ && -d $HOME/sw/branch ]]; then
    find $HOME/sw/branch -mindepth 1 -maxdepth 1 -type d -path '*/.*' -prune -o -type d -print0 |
    while IFS= read -r -d '' nvsrc; do 
        if [[ -d $nvsrc/drivers/OpenGL ]]; then 
            if [[ ! -f $nvsrc/drivers/OpenGL/.cursorignore ]]; then 
                ln -sf $HOME/sw/_cursor_workspace/.cursorignore $nvsrc/drivers/OpenGL/.cursorignore &&
                echo "Added symlink: $nvsrc/drivers/OpenGL/.cursorignore"
            fi 
            if [[ ! -d $nvsrc/drivers/OpenGL/.cursor ]]; then 
                ln -sf $HOME/sw/_cursor_workspace/.cursor $nvsrc/drivers/OpenGL/.cursor &&
                echo "Added symlink: $nvsrc/drivers/OpenGL/.cursor"
            fi 
            if [[ ! -f $nvsrc/drivers/OpenGL/.clangd ]]; then 
                ln -sf $HOME/sw/_cursor_workspace/.clangd $nvsrc/drivers/OpenGL/.clangd &&
                echo "Added symlink: $nvsrc/drivers/OpenGL/.clangd"
            fi 
        fi 
    done 
fi 

echo 
echo "All done!"
