#!/usr/bin/env bash
trap 'exit 130' INT

home_files=()
while IFS= read -r -d '' file; do 
    case "$file" in 
        *.tar|*.tar.gz|*.tgz|*.zip|*.tar.bz2|*.tar.xz) continue ;;
        *.run|*.so|*.deb|*libnvidia-*.so*) continue ;;
    esac 
    home_files+=("$file")
done < <(find "$HOME" -maxdepth 1 -type f -not -name '.*' -print0)

if ((${#home_files[@]})); then 
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

    echo "Files to upload (~/.rsyncignore applied):"
    ( IFS=$'\n'; echo "${home_files[*]}" )
    echo 

    ssh wanliz@$remote_ip "mkdir -p /mnt/d/${USER}@$(hostname)"
    rsync -lth --info=progress2 -e 'ssh -o StrictHostKeyChecking=accept-new' "${home_files[@]}" wanliz@$remote_ip:/mnt/d/${USER}@$(hostname)/
fi 

