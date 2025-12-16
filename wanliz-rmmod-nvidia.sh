#!/usr/bin/env bash

rmmod_recur() {
    local mod="$1"
    local recursive="${2:-}"

    if [[ -z $recursive ]]; then
        sudo -v || return 1
        rm -f /tmp/rmmod.restore

        if [[ $mod == nvidia ]] && command -v nvidia-smi >/dev/null 2>&1; then
            if nvidia-smi -q 2>/dev/null | grep -qiE 'Persistence Mode\s*:\s*Enabled'; then
                sudo nvidia-smi -pm 0 && echo "Disabled persistence mode"
                echo "sudo nvidia-smi -pm 1" >> /tmp/rmmod.restore
            fi
        fi

        if systemctl is-active --quiet display-manager; then
            sudo systemctl stop display-manager && echo "Stopped display-manager"
            echo "sudo systemctl start display-manager" >> /tmp/rmmod.restore
        fi
    fi

    if sudo rmmod $mod 2>/dev/null; then
        echo "Removed $mod"
        return 0
    fi

    local rmmod_out
    rmmod_out="$(sudo rmmod $mod 2>&1 || true)"

    if [[ $rmmod_out =~ in\ use\ by:\ (.+)$ ]]; then
        local dep
        for dep in ${BASH_REMATCH[1]}; do
            rmmod_recur "$dep" recursive || return 1
        done

        sudo rmmod $mod 2>/dev/null || true
        if [[ ! -d /sys/module/$mod ]]; then
            echo "Removed $mod"
            return 0
        fi
    fi

    # Kill userspace holders (device nodes)
    mapfile -t pids < <(sudo lsof -t /dev/dri/card* /dev/dri/renderD* /dev/nvidia* 2>/dev/null | sort -u)

    local pid cgroup unit scope sid
    for pid in "${pids[@]}"; do
        [[ $pid =~ ^[0-9]+$ ]] || continue
        [[ $pid -eq 1 || $pid -eq $$ ]] && continue
        [[ -r /proc/$pid/cgroup ]] || continue

        cgroup="$(< /proc/$pid/cgroup)"

        # Stop only system services
        unit="$(printf '%s\n' "$cgroup" | grep -oE 'system\.slice/[^/]+\.service' | head -n1 | sed 's@.*/@@')"
        if [[ -n $unit ]]; then
            sudo systemctl stop "$unit" && {
                echo "Stopped $unit"
                echo "sudo systemctl start $unit" >> /tmp/rmmod.restore
                sleep 2
            }
        fi

        # Terminate logind session scopes (Xorg case)
        scope="$(printf '%s\n' "$cgroup" | grep -oE 'session-[0-9]+\.scope' | head -n1)"
        if [[ $scope =~ session-([0-9]+)\.scope ]]; then
            sid="${BASH_REMATCH[1]}"
            sudo loginctl terminate-session "$sid" && {
                echo "Terminated login session $sid"
                sleep 2
            }
        fi

        # Kill the pid if still alive
        if [[ -e /proc/$pid ]]; then
            sudo kill -TERM $pid 2>/dev/null || true
            sleep 2
            [[ -e /proc/$pid ]] && sudo kill -KILL $pid 2>/dev/null || true
            echo "Killed $pid"
        fi
    done

    sudo rmmod $mod 2>/dev/null || true
    if [[ ! -d /sys/module/$mod ]]; then
        echo "Removed $mod"
        [[ -z $recursive && -s /tmp/rmmod.restore ]] && echo "Generated /tmp/rmmod.restore"
        return 0
    fi

    echo "Failed to remove $mod"
    return 1
}

rmmod_recur nvidia