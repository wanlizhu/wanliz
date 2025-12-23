#!/usr/bin/env bash
trap 'exit 130' INT

if [[ -z $DISPLAY ]]; then 
    export DISPLAY=:0
    echo "Fallback to DISPLAY=$DISPLAY"
fi 

ip=$(ip -4 route get $(getent ahostsv4 1.1.1.1 | awk 'NR==1{print $1}') | sed -n 's/.* src \([0-9.]\+\).*/\1/p')
echo "My IP: $ip"
if [[ -d /wanliz_sw_windows_wsl2 ]]; then
    nvsrc_version=$(cat /wanliz_sw_windows_wsl2/workingbranch/drivers/common/inc/nvUnixVersion.h | grep '#define' | grep NV_VERSION_STRING | awk -F'"' '{print $2}')
    echo "NVIDIA Source Code Version: $nvsrc_version"
else
    echo "NVIDIA Source Code Version: N/A"
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
echo "NVIDIA GPU Devices Found:"
nvidia-smi --query-gpu=index,pci.bus_id,name,compute_cap --format=csv,noheader | while IFS=, read -r idx bus name cc; do
    bus=$(echo "$bus" | awk '{{$1=$1}};1' | sed 's/^00000000/0000/' | tr 'A-Z' 'a-z')
    sys="/sys/bus/pci/devices/$bus"
    node=$(cat "$sys/numa_node" 2>/dev/null || echo -1)         # -1 means no NUMA info
    cpus=$(cat "$sys/local_cpulist" 2>/dev/null || echo '?')
    printf "GPU: %s    Name: %s    PCI: %s    NUMA node: %s    CPUs: %s\n" "$idx" "$name" "$bus" "$node" "$cpus"
done

echo 
echo "NVIDIA Kernel Version: $(cat /sys/module/nvidia/version)"
nvidia-smi -q | grep -i 'GSP Firmware Version' | sed 's/^[[:space:]]*//' | tr -s ' ' 

echo 
modinfo nvidia | egrep 'filename|version|firmware'

echo 
cat /proc/driver/nvidia/version

echo 
file /usr/lib/$(uname -m)-linux-gnu/libnvidia-glcore.so.*

echo 
echo "List PIDs using nvidia module:"
sudo lsof -w -n /dev/nvidia* | awk 'NR>1{{print $2}}' | sort -un | while read -r pid; do
    printf "PID=%-7s %s\n" "$pid" "$(tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null || ps -o args= -p "$pid")"
done

if [[ $1 == -d || $1 == --dump ]]; then 
    rm -f $HOME/system-info.txt
    for module in nvidia nvidia_uvm nvidia_drm nvidia_modeset; do 
        echo "===== BEGIN /proc/driver/$module/params =====" >> $HOME/system-info.txt
        cat /proc/driver/$module/params >> $HOME/system-info.txt
        echo "===== END   /proc/driver/$module/params =====" >> $HOME/system-info.txt
    done 
    echo 
    echo echo "===== BEGIN kernel config =====" >> $HOME/system-info.txt
    for param in $(find /sys/module -path '*/parameters/*' -type f -print | grep nvidia); do 
        echo "$param: $(sudo cat $param)"
    done 
    echo echo "===== END   kernel config =====" >> $HOME/system-info.txt
    echo 
fi 