#!/usr/bin/env bash

if [[ -z $P4CLIENT ]]; then 
    eval "$(p4env -print)"
fi 

time p4 sync  
resolve_files=$(p4 resolve -n $P4ROOT/... 2>/dev/null)
if [[ ! -z $resolve_files ]]; then 
    echo "Need resolve, trying auto-merge"
    p4 resolve -am $P4ROOT/... 
    conflict_files=$(p4 resolve $P4ROOT/... 2>/dev/null)
    if [[ ! -z $conflict_files ]]; then 
        echo "$(echo $conflict_files | wc -l) conflict files remain [Manual Merge]"
        echo $conflict_files
    else
        echo "No manual resolved needed"
    fi
else
    echo "No resolves needed"
fi 