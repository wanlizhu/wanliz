#!/usr/bin/env bash

if [[ -z $1 ]]; then 
    echo "=== NFS Exports ==="
    sudo exportfs -v | awk '/^\/|^\.\// {print $1}' | sort -u
    echo 
    echo "=== SMB Exports ==="
    sudo testparm -s 2>/dev/null | awk '
        /^\[.*\]$/ { sec=$0; gsub(/^\[|\]$/,"",sec); next }
        tolower($0) ~ /^[ \t]*path[ \t]*=/ {
        p=$0; sub(/^[ \t]*path[ \t]*=[ \t]*/,"",p);
        print sec "\t" p
        }' | grep -Ev '^(global|printers|print\$|homes)$' | column -t  
elif [[ -d "$1" ]]; then
    if [[ ! -z $(sudo exportfs -v | grep "$1") ]]; then 
        echo "Sharing $1 via NFS ... [SKIPPED]"
    else 
        echo "$1 *(rw,sync,insecure,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports >/dev/null 
        sudo exportfs -ra 
        sudo systemctl enable --now nfs-kernel-server
        sudo systemctl restart nfs-kernel-server
        echo "Sharing $1 via NFS ... [OK]"
    fi 

    if [[ ! -z $(testparm -s | grep "$1") ]]; then 
        echo "Sharing $1 via SMB ... [SKIPPED]"
    else
        if ! pdbedit -L -u $USER >/dev/null 2>&1; then
            sudo smbpasswd -a $USER 
        fi 
        if ! grep -q '^\[global\][[:space:]]*$' /etc/samba/smb.conf; then 
            echo '' | sudo tee -a /etc/samba/smb.conf >/dev/null
            echo '[global]' | sudo tee -a /etc/samba/smb.conf >/dev/null
            echo '   map to guest = Bad Password' | sudo tee -a /etc/samba/smb.conf >/dev/null
        fi 
        shared_name=$(basename "$1")
        echo "" | sudo tee -a /etc/samba/smb.conf >/dev/null
        echo "[$shared_name]" | sudo tee -a /etc/samba/smb.conf >/dev/null
        echo "   path = $1" | sudo tee  -a /etc/samba/smb.conf >/dev/null
        echo "   public = yes" | sudo tee -a /etc/samba/smb.conf >/dev/null
        echo "   guest ok = yes" | sudo tee -a /etc/samba/smb.conf >/dev/null
        echo "   force user = $USER" | sudo tee -a /etc/samba/smb.conf >/dev/null
        echo "   writable = yes" | sudo tee -a /etc/samba/smb.conf >/dev/null
        echo "   create mask = 0777" | sudo tee -a /etc/samba/smb.conf >/dev/null
        echo "   directory mask = 0777" | sudo tee -a /etc/samba/smb.conf >/dev/null
        sudo testparm -s || { echo '/etc/samba/smb.conf is invalid'; exit 1; }
        sudo systemctl enable --now smbd
        sudo systemctl restart smbd
        echo "Sharing $1 via SMB ... [OK]"
    fi 
fi 