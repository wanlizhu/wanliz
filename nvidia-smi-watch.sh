#!/usr/bin/env bash
trap 'exit 130' INT
set -euo pipefail

PROC_NAME=
OUTPUT_FILE=$HOME/nvidia-smi-watch.log 
INTERVAL_MS=200
while (( $# )); do
    case $1 in 
        -p|-proc) shift; PROC_NAME=$1 ;;
        -o|-output) shift; OUTPUT_FILE=$1 ;;
        -ms) shift; INTERVAL_MS=$1 ;;
        --) shift; break ;;
        *) break ;;
    esac
    shift 
done 

if [[ -z $PROC_NAME ]]; then
    echo "Missing option: [-p|-proc] <PROC_NAME>"
    exit 1
fi 

bash -lic "
    trap 'exit 130' INT
    set -euo pipefail
    rm -f /tmp/stop 

    while :; do 
        APP_PID=\$(pgrep -n -x \"$PROC_NAME\" 2>/dev/null || true)
        [[ ! -z \$APP_PID ]] && break 
        echo \"Wait for named proc: $PROC_NAME\"
        sleep 0.5
        if [[ -f /tmp/stop ]]; then
            exit 
        fi 
    done

    echo \"Running nvidia-smi in background ...\"
    nvidia-smi --query-gpu=timestamp,clocks.current.graphics,clocks.current.memory --format=csv,noheader,nounits -lms $INTERVAL_MS > $OUTPUT_FILE &
    SMI_PID=\$!

    while kill -0 \$APP_PID 2>/dev/null; do 
        sleep 0.5
    done 
    kill -INT \$SMI_PID 2>/dev/null  
" &

"$@"