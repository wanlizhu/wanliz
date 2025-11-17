#!/usr/bin/env bash

if [[ -z $1 ]]; then 
    pushd ~/wanliz >/dev/null || exit 1
    git add .
    git commit -m "auto push from $(hostname) at $(date)"
    git push 
    popd >/dev/null 
elif [[ $1 == "home" ]]; then 
    home_files=()
    while IFS= read -r -d '' file; do 
        case "$file" in 
            *.run|*.tar|*.tar.gz|*.tgz|*.zip|*.so|*.deb|*.tar.bz2|*.tbz|*.tbz2|*.tar.xz|*.txz|*.tar.zst|*.tzst|*.tar.lz4|*.tlz4) continue ;;
        esac 
        home_files+=("$file")
    done < <(find "$HOME" -maxdepth 1 -type f -not -name '.*' -print0)
    
    if ((${#home_files[@]})); then 
        if [[ ! -f ~/.push_host ]]; then 
            read -p "Host: " host
            read -p "User: " user
            echo "$user@$host" >~/.push_host
        fi 

        ssh $(cat ~/.push_host) "mkdir -p /mnt/d/${USER}@$(hostname)"
        rsync -lth --info=progress2 -e 'ssh -o StrictHostKeyChecking=accept-new' "${home_files[@]}" $(cat ~/.push_host):/mnt/d/${USER}@$(hostname)/
    fi 
fi 