#!/usr/bin/env bash

if [[ -z $DISPLAY ]]; then 
    export DISPLAY=:0
    echo "Fallback to DISPLAY=$DISPLAY"
fi 

if [[ -z $(sudo cat /etc/gdm3/custom.conf | grep -v '^#' | grep "WaylandEnable=false") ]]; then 
    echo "Disable wayland before starting VNC server"
    exit 0
fi 

x11vnc -display :0  -rfbport 5900 -noshm -forever -noxdamage -repeat -shared -bg -o $HOME/x11vnc.log \
    && echo "Starting VNC server on :5900 in background ... [OK]" \
    || cat $HOME/x11vnc.log
