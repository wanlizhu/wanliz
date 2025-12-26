#!/usr/bin/env bash
trap 'exit 130' INT

if [[ -z $DISPLAY ]]; then 
    export DISPLAY=:0
    echo "Environment variable DISPLAY requires a valid value"
    echo "Fallback to DISPLAY=$DISPLAY"
fi 

read -p "Is this a headless system? [Yes/n]: " headless
read -p "On success, run openbox in bg? [yes/No]: " start_openbox
read -p "On success, run x11vnc  in bg? [yes/No]: " start_x11vnc 
[[ -z ${start_openbox//[[:space:]]/} ]] && start_openbox=no
[[ -z ${start_x11vnc//[[:space:]]/} ]] && start_x11vnc=no
            
if [[ ! -z $(pidof Xorg) ]]; then 
    read -p "Press [Enter] to kill running X server: "    
    sudo pkill -TERM -x Xorg
    sleep 1
fi 

screen -ls | awk '/Detached/ && /bareX/ {{ print $1 }}' | while IFS= read -r session; do
    screen -S "$session" -X stuff $'\r'
done

if [[ $headless =~ ^[[:space:]]*([yY]([eE][sS])?)?[[:space:]]*$ ]]; then 
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
            
if [[ $start_openbox =~ ^[[:space:]]*([yY]([eE][sS])?)?[[:space:]]*$ ]]; then 
    screen -S openbox -dm openbox
    if [[ ! -z $(pidof openbox) ]]; then 
        echo "Starting openbox on $DISPLAY ... [OK]"
    else
        echo "Starting openbox on $DISPLAY ... [FAILED]"
    fi 
fi

if [[ $start_x11vnc =~ ^[[:space:]]*([yY]([eE][sS])?)?[[:space:]]*$ ]]; then 
    gdm_conf=""
    for f in /etc/gdm3/custom.conf /etc/gdm3/daemon.conf; do
        [[ -f $f ]] && gdm_conf=$f && break
    done

    if [[ -n $gdm_conf ]]; then
        if ! grep -Eq '^[[:space:]]*WaylandEnable[[:space:]]*=[[:space:]]*false' "$gdm_conf"; then
            echo "Wayland is still enabled in $gdm_conf. Set WaylandEnable=false and restart GDM, then re-run."
            exit 1
        fi
    fi

    x11vnc -display :0  -rfbport 5900 -noshm -forever -noxdamage -repeat -shared -bg -o $HOME/x11vnc.log \
        && echo "Starting VNC server on :5900 in background ... [OK]" \
        || cat $HOME/x11vnc.log
fi