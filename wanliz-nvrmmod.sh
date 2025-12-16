#!/usr/bin/env bash

function rmmod_recur() {
    if [[ -z $2 ]]; then 
        rm -f /tmp/rmmod.restore
        if [[ $1 == nvidia && ! -z $(which nvidia-smi) ]]; then 
            if [[ ! -z $(nvidia-smi -q | grep -i "Persistence Mode" | grep "Enabled") ]]; then 
                sudo nvidia-smi -pm 0
                echo "sudo nvidia-smi -pm 1" >> /tmp/rmmod.restore
            fi 
        fi 
    fi 

    if sudo rmmod $1 2>/dev/null; then 
        echo "Removed module $1"
        return 0
    fi 

    # Remove kernel module dependencies
    local rmmod_out=$(sudo rmmod $1 2>&1) || true 
    if [[ $rmmod_out =~ in\ use\ by:\ (.+)$ ]]; then 
        local mod_deps="${BASH_REMATCH[1]}"
        local mod_name 
        for mod_name in $mod_deps; do 
            rmmod_recur $mod_name 'recursive-called' || return 1
        done 

        sudo rmmod $1 2>/dev/null 
        if [[ -z $(lsmod | grep -q "^$1") ]]; then 
            echo "Removed $1"
            return 0
        else 
            echo "Failed to remove $1"
        fi 
    fi 
    # Remove userspace refcount holders 
    sudo lsof -t /dev/dri/card* /dev/dri/renderD* /dev/nvidia* 2>/dev/null > /tmp/nvidia_refcount_holders 
    awk '{for (i=1; i<=NF; i++) print $i}' /tmp/nvidia_refcount_holders | sort -u | while IFS= read -r pid; do 
        if [[ -e /proc/$pid/cgroup ]]; then 
            cgroup=$(cat /proc/$pid/cgroup)
            regex='/([^/]+)\.service$'
            if [[ $cgroup =~ $regex ]]; then
                unit="${BASH_REMATCH[1]}"
                sudo systemctl stop $unit && {
                    echo "Stopped $unit"
                    echo "sudo systemctl start $unit" >> /tmp/rmmod.restore
                }
                sleep 2
            fi
        fi 

        if [[ -e /proc/$pid ]]; then 
            [[ $pid =~ ^[0-9]+$ ]] || continue
            [[ $pid -eq 1 || $pid -eq $$ ]] && continue
            sudo kill -TERM $pid && sleep 2
            if [[ -e /proc/$pid ]]; then 
                sudo kill -9 $pid 
            fi 
        fi 
    done 

    # Retry without dependencies and refcount holders 
    sudo rmmod $1 2>/dev/null 
    if [[ -z $(lsmod | grep -q "^$1") ]]; then 
        echo "Removed $1"
        returncode=0
    else 
        echo "Failed to remove $1"
        returncode=1
    fi 

    if [[ -z $2 && -f /tmp/rmmod.restore ]]; then 
        echo "Generated /tmp/rmmod.restore"
    fi 

    return $returncode
}

rmmod_recur nvidia