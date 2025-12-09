#!/usr/bin/env bash

sudo rm -f /tmp/nvrmmod.restore 
sudo lsof -w -n /dev/nvidia* | awk 'NR>1{{print $2}}' | sort -un | while read -r pid; do
    printf "%-7s;%s\n" "$pid" "$(tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null || ps -o args= -p "$pid")"
done > /tmp/nvidia_cmds

nvidia_services=$(systemctl list-units --type=service --all  | grep nvidia | grep ' active' | awk '{print $1}' | xargs)
for name in gdm sddm lightdm openbox nvsm-core $nvidia_services; do 
    service_name=$(systemctl list-units --type=service | grep -i $name | awk '{print $1}')
    if [[ ! -z $service_name ]]; then 
        sudo systemctl stop $service_name && echo "Stopped $service_name"
        echo "sudo systemctl start $service_name && echo \"Started $service_name\"; " >>/tmp/nvrmmod.restore
    fi 
done 
if [[ ! -z $(cat /tmp/nvidia_cmds | grep 'nvidia-persistenced') ]]; then 
    if [[ ! -z $(which nvidia-persistenced) && -z $(systemctl list-units --type=service | grep -i 'nvidia-persistenced') ]]; then 
        sudo kill -9 $(cat /tmp/nvidia_cmds | grep 'nvidia-persistenced' | awk -F';' '{print $1}') && echo "Killed nvidia-persistenced"
        echo "sudo $(cat /tmp/nvidia_cmds | grep 'nvidia-persistenced' | awk -F';' '{print $2}')" >>/tmp/nvrmmod.restore
    fi 
fi 
if [[ ! -z $(nvidia-smi -q | grep -i "Persistence Mode" | grep "Enabled") ]]; then 
    sudo nvidia-smi -pm 0
    echo "sudo nvidia-smi -pm 1" >>/tmp/nvrmmod.restore
fi 

remove_pkg_drivers=
if [[ $remove_pkg_drivers == 1 ]]; then 
    echo "Removing nvidia drivers installed through packages ..."
    sudo apt-get purge -y $(dpkg -l | awk '/^ii[[:space:]]+libnvidia-/{print $2}')
    for pkg in nvidia-driver-open nvidia-dkms-open nvidia-open \
            nvidia-settings nvidia-modprobe nvidia-persistenced \
            nvidia-firmware nvidia-kernel-common nvidia-kernel-source-open
    do
        if dpkg -s $pkg >/dev/null 2>&1; then
            sudo apt purge -y $pkg
        fi
    done
fi 

sudo rm -f /tmp/nvidia_pids
sudo lsof  -t /dev/nvidia* /dev/dri/{card*,renderD*} 2>/dev/null >>/tmp/nvidia_pids
sudo grep -El 'lib(nvidia|cuda|GLX_nvidia|EGL_nvidia|nvoptix|nvrm|nvcuvid)' /proc/*/maps 2>/dev/null | sed -E 's@/proc/([0-9]+)/maps@\1@' >>/tmp/nvidia_pids 
awk '{for (i=1; i<=NF; i++) print $i}' /tmp/nvidia_pids | sort -u | while IFS= read -r pid; do 
    [[ $pid =~ ^[0-9]+$ ]] || continue
    [[ $pid -eq 1 || $pid -eq $$ ]] && continue
    sudo kill -9 $pid  && echo "Killing $pid ... [OK]" || echo "Killing $pid ... [FAILED]"
done 
