#!/usr/bin/env bash

if [[ -z $DISPLAY ]]; then 
    export DISPLAY=:0
    echo "Fallback to DISPLAY=$DISPLAY"
fi 

echo 
echo "X server info:"
if timeout 2s bash -lc 'command -v xdpyinfo >/dev/null && xdpyinfo >/dev/null 2>&1 || xset q >/dev/null 2>&1'; then 
    echo "X($DISPLAY) is online"
    echo "XDG_SESSION_TYPE=:$XDG_SESSION_TYPE"
    xrandr | grep current
    glxinfo | grep -i 'OpenGL renderer'
else 
    echo "X($DISPLAY) is down or unauthorized"
fi 

echo 
echo "Nvidia GPUs detected:"
nvidia-smi --query-gpu=index,pci.bus_id,name,compute_cap --format=csv,noheader | while IFS=, read -r idx bus name cc; do
    bus=$(echo "$bus" | awk '{{$1=$1}};1' | sed 's/^00000000/0000/' | tr 'A-Z' 'a-z')
    sys="/sys/bus/pci/devices/$bus"
    node=$(cat "$sys/numa_node" 2>/dev/null || echo -1)         # -1 means no NUMA info
    cpus=$(cat "$sys/local_cpulist" 2>/dev/null || echo '?')
    printf "GPU: %s    Name: %s    PCI: %s    NUMA node: %s    CPUs: %s\n" "$idx" "$name" "$bus" "$node" "$cpus"
done

echo 
nvidia-smi | grep "Driver Version"
nvidia-smi -q | grep -i 'GSP Firmware Version' | sed 's/^[[:space:]]*//'

echo 
modinfo nvidia | egrep 'filename|version'
file /usr/lib/$(uname -m)-linux-gnu/libnvidia-glcore.so.*

echo 
echo -e "\nList PIDs using nvidia module:"
sudo lsof -w -n /dev/nvidia* | awk 'NR>1{{print $2}}' | sort -un | while read -r pid; do
    printf "PID=%-7s %s\n" "$pid" "$(tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null || ps -o args= -p "$pid")"
done