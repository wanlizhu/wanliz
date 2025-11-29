#!/usr/bin/env bash

$(realpath $(dirname $0))/install-symbolic-links.sh || exit 1

# Run target app with args
inspect-gpu-perf-info "$@" 2>/tmp/igpi.txt

# Run post-process on logs
if [[ ! -f /tmp/igpi.txt ]] || ! grep -q '[^[:space:]]' /tmp/igpi.txt; then 
    echo "Invalid logs: /tmp/igpi.txt"
    exit 1
fi 

echo "Logs: /tmp/igpi.txt"