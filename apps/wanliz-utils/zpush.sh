#!/usr/bin/env bash

if [[ -z $1 ]]; then 
    pushd ~/wanliz >/dev/null || exit 1
    if grep -q 'url = https://github.com' .git/config; then
        read -s -p "All-in-one password: " password 
        echo 
        token=$(echo 'U2FsdGVkX1/9aV2rUTUL16lv0xm+oXZGRBQ2Sh4BAaAA3IS0Y/ftMKj6Ka8ws+5UcmvtWTpG+I37ykGjBG+EtA==' | openssl enc -aes-256-cbc -d -pbkdf2 -a -pass "pass:$password")
        sed -i "s|url = https://github.com|url = https://wanliz:$token@github.com|" .git/config
    fi
    git add .
    git commit -m "auto push from $(hostname) at $(date)"
    git push || {
        git pull 
        git push 
    }
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
        if [[ -f ~/.push_host ]]; then 
            if ! ping -c 1 -W 3 "$(cat ~/.push_host | awk -F'@' '{print $2}')" &>/dev/null; then 
                sudo rm -f ~/.push_host
            fi  
        fi 
        if [[ ! -f ~/.push_host ]]; then 
            read -p "Host: " host
            read -p "User: " user
            echo "$user@$host" >~/.push_host
        fi 

        if ! ssh \
            -o ConnectTimeout=3 \
            -o BatchMode=yes \
            -o PreferredAuthentications=publickey \
            -o PasswordAuthentication=no \
            -o KbdInteractiveAuthentication=no \
            -o StrictHostKeyChecking=accept-new \
            user@remote 'true' >/dev/null 2>&1; then
            if [[ -f ~/.ssh/id_ed25519 ]]; then 
                ssh-copy-id -i ~/.ssh/id_ed25519.pub $(cat ~/.push_host)
            fi 
        fi

        echo "Making dirs on remote if missing ... "
        ssh $(cat ~/.push_host) "mkdir -p /mnt/d/${USER}@$(hostname)"
        echo "Uploading home folder files ... "
        rsync -lth --info=progress2 -e 'ssh -o StrictHostKeyChecking=accept-new' "${home_files[@]}" $(cat ~/.push_host):/mnt/d/${USER}@$(hostname)/
    fi 
fi 