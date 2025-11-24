#!/usr/bin/env bash

sudo rm -f /tmp/nvrmmod.restore 
for name in gdm sddm lightdm openbox; do 
    service_name=$(systemctl list-units --type=service | grep -i $name | awk '{print $1}')
    if [[ ! -z $service_name ]]; then 
        sudo systemctl stop $service_name && echo "Stopped $service_name"
        echo "sudo systemctl start $service_name && echo \"Started $service_name\"; " >/tmp/nvrmmod.restore
    fi 
done 

sudo rm -f /tmp/nvidia_pids
sudo systemctl stop sddm lightdm nvidia-persistenced 2>/dev/null || true
sudo lsof  -t /dev/nvidia* /dev/dri/{card*,renderD*} 2>/dev/null >>/tmp/nvidia_pids
sudo grep -El 'lib(nvidia|cuda|GLX_nvidia|EGL_nvidia|nvoptix|nvrm|nvcuvid)' /proc/*/maps 2>/dev/null | sed -E 's@/proc/([0-9]+)/maps@\1@' >>/tmp/nvidia_pids 
awk '{for (i=1; i<=NF; i++) print $i}' /tmp/nvidia_pids | sort -u | while IFS= read -r pid; do 
    [[ $pid =~ ^[0-9]+$ ]] || continue
    [[ $pid -eq 1 || $pid -eq $$ ]] && continue
    sudo kill -9 $pid  && echo "Killing $pid ... [OK]" || echo "Killing $pid ... [FAILED]"
done 
