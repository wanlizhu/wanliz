#!/usr/bin/env bash

if [[ -z $P4CLIENT ]]; then 
    eval "$(p4env.sh -print)"
fi 

ofiles=$(p4 opened -C $P4CLIENT //... 2>/dev/null)
if [[ ! -z $ofiles ]]; then
    echo "=== Files Opened for Edit ==="
    echo $ofiles
fi 

read -p "Reconcile to collect local changes? [Y/n]: " choice 
if [[ -z $choice || $choice == "y" ]]; then 
    afiles=$(p4 reconcile -n -a $P4ROOT/... 2>/dev/null || true)
    if [[ ! -z $afiles ]]; then 
        echo "=== Files Not Tracked ==="
        echo "$afiles"     
    fi  
    echo 
    dfiles=$(p4 reconcile -n -d $P4ROOT/... 2>/dev/null || true)
    if [[ ! -z $dfiles ]]; then 
        echo "=== Files Deleted ==="
        echo "$dfiles"   
    fi  
fi 