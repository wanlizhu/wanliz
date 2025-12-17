#!/usr/bin/env bash
trap 'exit 130' INT

if [[ -z $DISPLAY ]]; then 
    export DISPLAY=:0
    echo "Fallback to DISPLAY=$DISPLAY"
fi 

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
