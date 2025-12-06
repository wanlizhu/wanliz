#!/usr/bin/env bash

if [[ -z $DISPLAY ]]; then 
    export DISPLAY=:0
    echo "Fallback to DISPLAY=$DISPLAY"
fi 

read -p "Is this machine a headless system? [Y/n]: " headless
read -p "Do you want to start openbox? [y/N]: " start_openbox
read -p "Do you want to start x11vnc? [y/N]: " start_x11vnc 

if [[ $(nvidia-smi --query-gpu=name --format=csv,noheader) == "NVIDIA GB10" ]]; then 
    read -p "Do you want to run spark-config? [Y/n]: " spark_config
    if [[ -z $spark_config || $spark_config == "y" ]]; then 
        spark-config.sh 
    fi 
fi 
            
if [[ ! -z $(pidof Xorg) ]]; then 
    read -p "Press [Enter] to kill running X server: "    
    sudo pkill -TERM -x Xorg
    sleep 1
fi 

screen -ls | awk '/Detached/ && /bareX/ {{ print $1 }}' | while IFS= read -r session; do
    screen -S "$session" -X stuff $'\r'
done

if [[ -z $headless || $headless == "y" ]]; then 
    busID=$(nvidia-xconfig --query-gpu-info | sed -n '/PCI BusID/{{s/^[^:]*:[[:space:]]*//;p;q}}')
    sudo nvidia-xconfig -s -o /etc/X11/xorg.conf \
        --force-generate --mode-debug --layout=Layout0 --render-accel --cool-bits=4 \
        --mode-list=3840x2160 --depth 24 --no-ubb \
        --x-screens-per-gpu=1 --no-separate-x-screens --busid=$busID \
        --connected-monitor=GPU-0.DFP-0 --custom-edid=GPU-0.DFP-0:/mnt/linuxqa/nvtest/pynv_files/edids_db/ASUSPB287_DP_3840x2160x60.000_1151.bin 
    sudo screen -S bareX -dm bash -lci "__GL_SYNC_TO_VBLANK=0 X $DISPLAY -config /etc/X11/xorg.conf -logfile $HOME/X.log -logverbose 5 -ac +iglx"
else
    sudo screen -S bareX -dm bash -lci "__GL_SYNC_TO_VBLANK=0 X $DISPLAY -logfile $HOME/X.log -logverbose 5 -ac +iglx"
fi 

for i in $(seq 1 10); do
    sleep 1
    if xdpyinfo >/dev/null 2>&1; then 
        break
    fi
    if [[ -z $(pidof Xorg) ]]; then 
        echo "Failed to start X server"
        exit 1
    fi 
done

xhost + || true

fbsize=$(xrandr --current 2>/dev/null | sed -n 's/^Screen .* current \([0-9]\+\) x \([0-9]\+\).*/\1x\2/p;q')
if [[ $fbsize != "3840x2160" ]]; then 
    grep -E "Found 0 head on board" $HOME/X.log
    xrandr --fb 3840x2160
fi 
xrandr --current
            
if [[ $start_openbox == "y" ]]; then 
    screen -S openbox -dm openbox
fi

if [[ $start_x11vnc == "y" ]]; then 
    zstartvnc.sh 
fi