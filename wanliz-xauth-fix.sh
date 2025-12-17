#!/usr/bin/env bash
trap 'exit 130' INT

if [[ -z $DISPLAY ]]; then 
    export DISPLAY=:0
fi 

Xorg_pid=$(pgrep -ax Xorg 2>/dev/null | awk -v d="$DISPLAY" '$0 ~ (" " d "($| )") { print $1; exit }')
if [[ -z $Xorg_pid ]]; then 
    echo "No Xorg process found for DISPLAY=$DISPLAY"
    exit 1
fi 

function copy_xauth() {
    local src="$1" 
    local dst="$HOME/.Xauthority"
    cp "$src" "$dst" 2>/dev/null || {
        if sudo cp "$src" "$dst"; then 
            sudo chown $USER:$USER "$dst" && return 0
        fi  
    }
    return 1
}

function success_and_exit() {
    echo "Generated $HOME/.Xauthority"
    if [[ $1 == "-s" ]]; then 
        echo "Todo: define envvar XAUTHORITY to use it"
    else
        export XAUTHORITY="$HOME/.Xauthority"
        exec bash -i 
    fi 
    exit 0
}

echo "Checking cmdline args of process $Xorg_pid"
xauth_file=""
if [[ -r /proc/$Xorg_pid/cmdline ]]; then 
    args=()
    while IFS= read -r -d '' a; do 
        args+=("$a")
    done < /proc/$Xorg_pid/cmdline
    for ((i=0; i<${#args[@]}-1; i++)); do
        [[ ${args[i]} == "-auth" ]] && xauth_file=${args[i+1]} && break
    done 
fi 
if [[ -n $xauth_file && -f $xauth_file ]]; then 
    if copy_xauth "$xauth_file"; then 
        success_and_exit
    fi 
fi 

echo "Checking original .Xauthority"
Xorg_uid=$(stat -c '%u' "/proc/$Xorg_pid" 2>/dev/null || echo "")
if [[ -n $Xorg_uid ]]; then 
    Xorg_home=$(getent passwd "$Xorg_uid" | cut -d: -f6)
    if [[ -n $Xorg_home && -f "$Xorg_home/.Xauthority" ]]; then
        if copy_xauth "$Xorg_home/.Xauthority"; then
            success_and_exit 
        fi
    fi
fi 

echo "No usable .Xauthority file found"
echo "Trying to disable access control via xhost"
if xhost 2>/dev/null | grep -qi 'access control disabled'; then
    echo "Access control disabled for $DISPLAY"
    exit 0
fi

Xorg_user=$(getent passwd "$Xorg_uid" | cut -d: -f1)
if [[ -z $Xorg_user ]]; then
    echo "Unable to determine Xorg user for pid $Xorg_pid"
    exit 1
fi

echo "Trying to run xhost as $Xorg_user"
sudo -u "$Xorg_user" DISPLAY=$DISPLAY xhost + && {
    echo "Access control disabled for $DISPLAY"
} || {
    echo "Failed to run xhost as $Xorg_user"
}

echo "Failed to sync .Xauthority"
exit 1
