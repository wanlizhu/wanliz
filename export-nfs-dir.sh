#!/usr/bin/env bash
trap 'exit 130' INT

if [[ ! -z $(sudo exportfs -v | grep "$1") ]]; then 
    echo "$1 is already exported via NFS"
else 
    echo "$1 *(rw,sync,insecure,no_subtree_check,no_root_squash)" | sudo tee -a /etc/exports >/dev/null 
    sudo exportfs -ra || { echo "Failed to export $1"; exit 1; }
    sudo systemctl enable --now nfs-kernel-server
    sudo systemctl restart nfs-kernel-server
fi 