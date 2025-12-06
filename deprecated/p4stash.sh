#!/usr/bin/env bash

export P4PORT="p4proxy-sc.nvidia.com:2006"
export P4USER="wanliz"
export P4CLIENT="wanliz_sw_linux"
export P4ROOT="/wanliz_sw_linux"

p4 reconcile -e -a -d $P4ROOT/... >/dev/null || true
p4 change -o /tmp/stash
sed -i "s|<enter description here>|STASH: $(date '+%F %T')" /tmp/stash 
cl=$(p4 change -i </tmp/stash | awk '/^Change/ {print $2}')
p4 reopen -c $cl $P4ROOT/... >/dev/null || true 
p4 shelve -f -c $cl >/dev/null 
echo "Stashed into CL $cl"