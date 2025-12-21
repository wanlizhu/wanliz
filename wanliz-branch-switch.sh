#!/usr/bin/env bash
trap 'exit 130' INT

if [[ -z $P4ROOT ]]; then 
    export P4PORT="p4proxy-sc.nvidia.com:2006"
    export P4USER="wanliz"
    export P4CLIENT="wanliz_sw_windows_wsl2"
    export P4ROOT="/wanliz_sw_windows_wsl2"
fi 

echo "[1] $P4ROOT/workingbranch"
echo "[2] $P4ROOT/testingbranch"
read -e -i 1 -p "Select a branch folder to switch: " branch_index 
case $branch_index in 
    1) BRANCH=workingbranch ;;
    2) BRANCH=testingbranch ;;
    *) echo "Invalid branch index $branch_index"; exit 1 ;;
esac 

echo "Backing up untracked workspace files ..."
SRC=/wanliz_sw_windows_wsl2/$BRANCH/drivers/OpenGL
mkdir -p /mnt/d/wanliz_sw_windows_wsl2.backup/$BRANCH/drivers/OpenGL
rsync -ah --ignore-missing-args --info=progress2 \
    $SRC/_doc \
    $SRC/.cursor \
    $SRC/compile_commands.json \
    $SRC/*.code-workspace \
    /mnt/d/wanliz_sw_windows_wsl2.backup/$BRANCH/drivers/OpenGL/

oldbranch=$(p4 client -o | grep "$BRANCH/drivers/OpenGL" | head -1 | awk -F'/drivers' '{print $1}')
oldbranch=$(echo "$oldbranch" | sed 's/^[[:space:]]*//')
echo                       "The current branch: $oldbranch (mapped to $BRANCH)"
read -e -i "$oldbranch" -p "  Switch to branch: " newbranch
if [[ $oldbranch != $newbranch ]]; then
    p4 client -o | sed "s#$oldbranch#$newbranch#g" | p4 client -i
    p4 sync -k //$P4CLIENT/$BRANCH/...
    p4 clean -e -d //$P4CLIENT/$BRANCH/...
fi
oldchange=$(p4 changes -m1 "//$P4CLIENT/$BRANCH/...#have" | awk '{print $2}')
echo                       "The current change: $oldchange"
read -e -i "$oldchange" -p "  Switch to change: " newchange
if [[ $oldchange != $newchange ]]; then
    p4 sync //$P4CLIENT/$BRANCH/...@$newchange
fi