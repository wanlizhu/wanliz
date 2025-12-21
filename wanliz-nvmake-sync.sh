#!/usr/bin/env bash
trap 'exit 130' INT

if [[ -z $P4ROOT ]]; then 
    export P4ROOT="/home/wanliz/sw"
fi 

read -p "Reset $P4ROOT/branch/... ? [Y/n]: " reset_branch
if [[ -z $reset_branch || $reset_branch =~ ^([yY]([eE][sS])?)?$ ]]; then 
    p4 sync -k  $P4ROOT/branch/...
    p4 clean -e -d $P4ROOT/branch/...
fi 

echo 
echo -e "Todo: p4 revert -k -c default /home/wanliz/sw/... \t Abandon records but keep local changes"
echo -e "Todo: p4 sync --parallel=threads=32 $P4ROOT/branch/...@12345678 \t Sync to specified CL"
echo -e "Todo: p4 reconcile -f -m -M --parallel=32 -c default $P4ROOT/... \t P4v's reconcile"