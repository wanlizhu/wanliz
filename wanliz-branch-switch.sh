#!/usr/bin/env bash
trap 'exit 130' INT

if [[ -z $P4ROOT ]]; then 
    export P4PORT="p4proxy-sc.nvidia.com:2006"
    export P4USER="wanliz"
    export P4CLIENT="wanliz_sw_windows_wsl2"
    export P4ROOT="/wanliz_sw_windows_wsl2"
fi 

echo "Backing up untracked workspace files ..."
SRC=/wanliz_sw_windows_wsl2/workingbranch/drivers/OpenGL
mkdir -p /mnt/d/wanliz_sw_windows_wsl2.backup/workingbranch/drivers/OpenGL
rsync -ah --ignore-missing-args --info=progress2 \
    $SRC/_doc \
    $SRC/.cursor \
    $SRC/compile_commands.json \
    $SRC/*.code-workspace \
    /mnt/d/wanliz_sw_windows_wsl2.backup/workingbranch/drivers/OpenGL/

oldbranch=$(p4 client -o | grep 'drivers/OpenGL' | head -1 | awk -F'/drivers' '{print $1}')
oldbranch=$(echo "$oldbranch" | sed 's/^[[:space:]]*//')
echo                       "The current branch: $oldbranch"
read -e -i "$oldbranch" -p "  Switch to branch: " newbranch
if [[ $oldbranch != $newbranch ]]; then
    p4 client -o | sed "s#$oldbranch#$newbranch#g" | p4 client -i
    p4 sync -k //$P4CLIENT/workingbranch/...
    p4 clean -e -d //$P4CLIENT/workingbranch/...
fi
oldchange=$(p4 changes -m1 "//$P4CLIENT/workingbranch/...#have" | awk '{print $2}')
echo                       "The current change: $oldchange"
read -e -i "$oldchange" -p "  Switch to change: " newchange
if [[ $oldchange != $newchange ]]; then
    p4 sync //$P4CLIENT/workingbranch/...@$newchange
fi