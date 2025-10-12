#!/bin/bash

enableWM=
enableVNC=
while [[ $# -gt 1 ]]; do 
    case $2 in 
        wm) enableWM=1 ;;
        vnc) enableVNC=1 ;; 
    esac
    shift 
done 

if [[ ! -z $(pidof Xorg) ]]; then 
    read -p "Press [Enter] to kill running Xorg ($(pidof Xorg)): "
    sudo pkill Xorg
fi 

[[ -z $DISPLAY ]] && export DISPLAY=:0

screen -S bare-xorg bash -c "sudo X $DISPLAY -ac +iglx || read -p 'Press [Enter] to exit: '"
while [ ! -S /tmp/.X11-unix/X0 ]; do sleep 0.1; done
xrandr --fb 3840x2160  

if [[ -e $HOME/sandbag-tool ]]; then 
    sudo $HOME/sandbag-tool -unsandbag
    sudo $HOME/sandbag-tool -print 
fi 

if [[ $(uname -m) == aarch64 ]]; then 
    perfdebug=/mnt/linuxqa/wanliz/iGPU_vfmax_scripts/perfdebug
    sudo $perfdebug --lock_loose   set pstateId P0 && echo -e "set pstateId ... [OK]\n"
    #sudo $perfdebug --lock_strict  set dramclkkHz 8000000 && echo -e "set dramclkkHz ... [OK]\n"
    sudo $perfdebug --lock_strict  set gpcclkkHz  2000000 && echo -e "set gpcclkkHz  2000MHz ... [OK]\n"
    sudo $perfdebug --lock_loose   set xbarclkkHz 1800000 && echo -e "set xbarclkkHz 1800MHz ... [OK]\n"
    #sudo $perfdebug --lock_loose   set sysclkkHz  1800000 && echo -e "set sysclkkHz  ... [OK]\n"
    sudo $perfdebug --force_regime ffr && echo -e "Force regime ... [OK]\n"
    sleep 3
    echo "The current GPC Clock: $(nvidia-smi --query-gpu=clocks.gr --format=csv,noheader)"
    echo "The current GPC Clock: $(nvidia-smi --query-gpu=clocks.gr --format=csv,noheader)"
    echo "The current GPC Clock: $(nvidia-smi --query-gpu=clocks.gr --format=csv,noheader)" 
fi 

if [[ $enableVNC == 1 ]]; then
    [[ ! -e ~/.vnc/passwd ]] && x11vnc -storepasswd
    screen -S vnc-mirroring x11vnc -display $DISPLAY -auth ~/.Xauthority -noshm -forever --loop -noxdamage -repeat -shared
    sleep 2
    sudo ss -tulpn | grep -E "5900|5901|5902"
fi 

if [[ $enableWM == 1 ]]; then 
    openbox >/tmp/openbox.stdout 2>/tmp/openbox.stderr & disown 
    echo "Window manager (openbox) is running as $(pidof openbox) on $DISPLAY"
fi 