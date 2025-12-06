#!/usr/bin/env bash

if [[ -z $P4CLIENT ]]; then 
    eval "$(p4env.sh -print)"
fi 

p4 changes -s pending -u $P4USER -c $P4CLIENT | while read -r line; do 
    changelist=$(echo "$line" | awk '{print $2}')
    if [[ -z $(p4 opened -c $changelist 2>/dev/null) ]]; then
        echo "$line #shelved"
    else
        echo "$line #opened"
    fi
done 