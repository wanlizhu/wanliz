#!/usr/bin/env bash
trap 'exit 130' INT
if [[ $EUID == 0 || -z $(which sudo) ]]; then 
    sudo() { "$@"; }
fi 

if testparm -s 2>/dev/null | grep -q "^[[:space:]]*path[[:space:]]*=[[:space:]]*$1[[:space:]]*$"; then
    echo "$1 is already exported via SMB"
else
    if ! pdbedit -L -u $USER >/dev/null 2>&1; then
        sudo smbpasswd -a $USER 
    fi 

    if ! grep -q '^\[global\][[:space:]]*$' /etc/samba/smb.conf; then 
        echo '' | sudo tee -a /etc/samba/smb.conf >/dev/null
        echo '[global]' | sudo tee -a /etc/samba/smb.conf >/dev/null
        echo '   map to guest = Bad Password' | sudo tee -a /etc/samba/smb.conf >/dev/null
    fi 

    read -e -i $(basename "$1") -p "Export as: " exported_name 
    sudo tee -a /etc/samba/smb.conf >/dev/null <<EOF

[$exported_name]
    path = $1
    public = yes
    guest ok = yes
    force user = $USER
    writable = yes
    create mask = 0777 
    directory mask = 0777
EOF 

    sudo testparm -s || { echo "Failed to export $1"; exit 1; }
    sudo systemctl enable --now smbd
    sudo systemctl restart smbd
fi 