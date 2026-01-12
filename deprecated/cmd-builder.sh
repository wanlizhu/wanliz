#!/usr/bin/env bash
trap 'exit 130' INT

if [[ $1 == p4env ]]; then 
    echo 'export P4PORT="p4proxy-sc.nvidia.com:2006"
export P4USER="wanliz"
export P4CLIENT="wanliz_sw_windows_wsl2"
export P4ROOT="/home/wanliz/sw"'
fi 

if [[ $1 == nsys ]]; then 
    if [[ ! -e ~/nsight_systems/bin/nsys ]]; then 
        echo "$HOME/nsight_systems/bin/nsys doesn't exist"
        echo "Install Nsight systems: https://urm.nvidia.com/artifactory/swdt-nsys-generic/ctk/"
        exit 1
    fi 

    sampling_period=$($HOME/nsight_systems/bin/nsys profile --help=sampling 2>/dev/null | awk '
        /--sampling-period=/ {flag=1; next}
        flag && /Possible values are integers between/ {
            c=0
            for (i=1; i<=NF; i++) {
                s=$i
                gsub(/[^0-9]/, "", s)
                if (s != "") { nums[++c]=s }
            }
            if (c >= 2) {
                min=nums[1]
                if (nums[2] < min) min=nums[2]
                print min
            }
            exit
        }')
    metrics_freq=$($HOME/nsight_systems/bin/nsys profile --help=gpu 2>/dev/null | awk '
        /--gpu-metrics-frequency=/ {flag=1; next}
        flag && /Maximum supported frequency is/ {
            s=$0
            gsub(/[^0-9]/, "", s)
            print s
            exit
        }')
    echo "function nsys-record() {
: \${NAME:=perf_\$(basename \$1)_\$(date +%Y%m%d)}  
: \${API:=vulkan,opengl}
sudo $HOME/nsight_systems/bin/nsys profile \\
    --trace=osrt,nvtx,$API \\
    --vulkan-gpu-workload=individual \\
    --sample=process-tree \\
    --sampling-period=$sampling_period \\
    --samples-per-backtrace=1 \\
    --backtrace=dwarf \\
    --cpuctxsw=process-tree \\
    --syscall=process-tree \\
    --gpu-metrics-devices=all \\
    --gpu-metrics-frequency=$metrics_freq \\
    --stats=true \\
    --export=sqlite,text \\
    --resolve-symbols=true \\
    --force-overwrite=true \\
    --stop-on-exit=true \\
    --wait=all \\
    --show-output=true \\
    --output=\$NAME 
}
nsys-record <...>" 
fi 

if [[ $1 == ngfx ]]; then 
    if [[ ! -e ~/nsight_graphics/ ]]; then 
        echo "$HOME/nsight_graphics/ doesn't exist"
        echo "Install Nsight graphics: https://ngfx/builds-prerel/Grxa/"
        echo "Install Nsight graphics: https://ngfx/builds-nightly/Grfx/"
        echo "Install Nsight graphics: \\devrel\share\Devtools\NomadBuilds\latest\Internal (username is email)"
        exit 1
    fi 
fi 

if [[ $1 == perf ]]; then 
    if [[ ! -d $HOME/FlameGraph ]]; then 
        git clone https://github.com/brendangregg/FlameGraph $HOME/FlameGraph &>/dev/null 
    fi 
    if [[ ! -z $(which perf) ]]; then 
        if ! sudo perf stat true &>/dev/null; then 
            echo "$(which perf) doesn't work with $(uname -r)"
            exit 1
        fi 
    else
        echo "perf command doesn't exist"
        echo "Install perf command via apt"
        exit 1
    fi 

    echo "function perf-record() {  
    : \${NAME:=perf_\$(basename \$1)_\$(date +%Y%m%d)}  
    : \${FREQ:=\$(cat /proc/sys/kernel/perf_event_max_sample_rate | sed 's/.$//')} 
    sudo \$(which perf) record --freq=\$FREQ --call-graph=dwarf --timestamp --output=\$NAME -- \$@  
    sudo chmod a+r \$NAME 
    sudo perf script --no-inline --force --ns -F +pid -i \$NAME > \$NAME.perthread 
    sudo chmod 666 \$NAME.perthread 
    sudo perf script --no-inline --force --ns -i \$NAME | 
        \$HOME/FlameGraph/stackcollapse-perf.pl | 
        \$HOME/FlameGraph/stackcollapse-recursive.pl | 
        \$HOME/FlameGraph/flamegraph.pl \\
            --title=\$NAME \\
            --subtitle=\"Host: \$(uname -m), Kernel: \$(uname -r), Driver: \$(modinfo nvidia | egrep '^version:' | awk '{print \$2}'), Timestamp: \$(date +'%Y-%m-%d %H:%M:%S')\" \\
            --countname='samples' \\
        > \$NAME.svg 
    sudo chmod 666 \$NAME.svg 
} 
perf-record <...>"
fi 

if [[ $1 == pi ]]; then 
    if [[ ! -e ~/SinglePassCapture/pic-x ]]; then 
        echo "$HOME/SinglePassCapture/pic-x doesn't exist"
        echo "Install PI: https://gitlab-master.nvidia.com/perf-inspector/gift/-/releases"
        exit 1
    fi 
fi 