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
        -r|-reset) 
            if [[ -f $HOME/nvidia-smi-watch.list ]]; then 
                kill -INT $(cat $HOME/nvidia-smi-watch.list)
                rm -f $HOME/nvidia-smi-watch.list
            fi 
        ;;
        --) shift; break ;;
        *) break ;;
    esac
    shift 
done 

if [[ -z $PROC_NAME ]]; then
    echo "Missing option: [-p|-proc] <PROC_NAME>"
    exit 1
fi 

nohup bash -lic "
    trap 'exit 130' INT
    set -euo pipefail

    while :; do 
        APP_PID=\$(pgrep -n -x \"$PROC_NAME\" 2>/dev/null || true)
        [[ ! -z \$APP_PID ]] && break 
        echo \"Wait for named proc: $PROC_NAME\"
        sleep 0.5
    done

    echo \"Running nvidia-smi in detached mode ...\"
    nvidia-smi --query-gpu=timestamp,clocks.current.graphics,clocks.current.memory --format=csv -lms $INTERVAL_MS > \"$OUTPUT_FILE\" &
    SMI_PID=\$!

    while kill -0 \$APP_PID 2>/dev/null; do 
        sleep 0.5
    done 

    echo \"Killing nvidia-smi\"
    [[ -d /proc/\$SMI_PID ]] && kill -INT \$SMI_PID 2>/dev/null  
    sleep 0.5 
    [[ -d /proc/\$SMI_PID ]] && kill -9 \$SMI_PID 2>/dev/null 
" &
echo " $!" >> $HOME/nvidia-smi-watch.list 
disown 

"$@"