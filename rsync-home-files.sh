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
    if [[ -f /tmp/rsync-to-ipv4 ]]; then 
        if ! sudo ping -c 1 -W 3 "$(cat /tmp/rsync-to-ipv4 2>/dev/null)"; then 
            sudo rm -f /tmp/rsync-to-ipv4
        fi  
    fi 
    if [[ ! -f /tmp/rsync-to-ipv4 ]]; then 
        read -p "Remote server IP: " remote_ip
        echo "$remote_ip" > /tmp/rsync-to-ipv4
    fi 

    echo "Files to upload:"
    echo "${home_files[@]}"

    remote_ip=$(cat /tmp/rsync-to-ipv4)
    ssh wanliz@$remote_ip "mkdir -p /mnt/d/${USER}@$(hostname)"
    rsync -lth --info=progress2 -e 'ssh -o StrictHostKeyChecking=accept-new' "${home_files[@]}" wanliz@$remote_ip:/mnt/d/${USER}@$(hostname)/
fi 

