#!/usr/bin/env bash

if [[ -z $P4CLIENT ]]; then 
    eval "$(p4env -print)"
fi 

changelist=$1
if [[ -z $changelist ]]; then 
    echo "Missing cmdline arguments:"
    echo "    \$1 - changelist to checkout"
    exit 1
fi 

# Revert only unchanged files 
p4 revert -a //... 2>/dev/null
changed_files="$(p4 opened //... 2>/dev/null || true)"
if [[ ! -z $opened_files ]]; then 
    echo "Sync aborted due to local changes of opened files:"
    echo "$opened_files"
    exit 1
fi 

time p4 sync //...@$changelist 
