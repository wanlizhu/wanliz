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

p4 describe -s $changelist
echo 
echo "Affected files (diff) ..."
echo 
p4 opened -c $changelist | awk '{print $1}' | p4 -x - diff -du 
