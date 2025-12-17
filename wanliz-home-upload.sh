#!/usr/bin/env bash

home_files=()
while IFS= read -r -d '' file_path; do 
    case "$file_path" in 
        *.run|*.tar|*.tar.gz|*.tgz|*.zip|*.so|*.deb|*.tar.bz2|*.tbz|*.tbz2|*.tar.xz|*.txz|*.tar.zst|*.tzst|*.tar.lz4|*.tlz4) continue ;;
        *nvperf_vulkan) continue ;;
        *libnvidia-*) continue ;;
    esac 
    home_files+=("$file_path")
done < <(find "$HOME" -maxdepth 1 -type f -not -name '.*' -print0)

if ((${#home_files[@]})); then 
    if [[ -f /tmp/remote.ip ]]; then 
        if ! sudo ping -c 1 -W 3 "$(cat /tmp/remote.ip 2>/dev/null)"; then 
            sudo rm -f /tmp/remote.ip
        fi  
    fi 
    if [[ ! -f /tmp/remote.ip ]]; then 
        read -p "Remote IP: " remote_ip
        echo "$remote_ip" > /tmp/remote.ip
    fi 

    remote_ip=$(cat /tmp/remote.ip)
    ssh wanliz@$remote_ip "mkdir -p /mnt/d/${USER}@$(hostname)"
    rsync -rDh --no-perms --no-owner --no-group --no-times --omit-dir-times --ignore-missing-args --info=progress2 -e 'ssh -o StrictHostKeyChecking=accept-new' "${home_files[@]}" wanliz@$remote_ip:/mnt/d/${USER}@$(hostname)/
fi 