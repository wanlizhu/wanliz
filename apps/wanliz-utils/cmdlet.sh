#!/usr/bin/env bash

case $1 in 
    rmlog) 
        echo "Envvar to enable RM loggings:"
        echo "__GL_DEBUG_MASK=RM __GL_DEBUG_LEVEL=30 __GL_DEBUG_OPTIONS=LOG_TO_FILE __GL_DEBUG_FILENAME=$HOME/RMLogs.txt"
    ;;
    clamp)
        echo "Filter text between start and end lines:"
        echo "<...> | awk '/AAAA/{flag=1; next} /ZZZZ/{flag=0} flag'"
    ;;
    nsight)
        echo "Install Nsight  systems: https://urm.nvidia.com/artifactory/swdt-nsys-generic/ctk/"
        echo "Install Nsight graphics: https://ngfx/builds-prerel/Grxa/"
        echo "Install Nsight graphics: https://ngfx/builds-nightly/Grfx/"
        echo "Install Nsight graphics: \\devrel\share\Devtools\NomadBuilds\latest\Internal (username is email)"
        echo 
        $0 nsys 
        echo 
        $0 ngfx 
    ;;
    nsys)
        echo "Launch Nsight systems from command line: "
        if [[ -e ~/nsight_systems/bin/nsys ]]; then 
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
            echo "sudo $HOME/nsight_systems/bin/nsys profile --trace=vulkan,opengl,cuda,nvtx,osrt --vulkan-gpu-workload=individual --sample=process-tree --sampling-period=$sampling_period --samples-per-backtrace=1 --backtrace=dwarf --cpuctxsw=process-tree --syscall=process-tree --gpu-metrics-devices=all --gpu-metrics-frequency=$metrics_freq --stats=true --export=sqlite,text --resolve-symbols=true --force-overwrite=true --stop-on-exit=true --wait=all --show-output=true --output=nsys_\$(hostname)_\$(date +%Y%m%d) <...>" 
        else
            echo "$HOME/nsight_systems/bin/nsys doesn't exist"
        fi 
    ;;
    ngfx)
        echo "Launch Nsight graphics from command line:"
        echo "TODO"
    ;;
    perf)
        
        if [[ ! -z $(which perf) ]]; then 
            if ! sudo perf stat true &>/dev/null; then 
                echo "$(which perf) doesn't work with $(uname -r)"
                exit 1
            fi 
        else
            echo "perf command doesn't exist"
            exit 1
        fi 

        echo "Launch GNU perf from command line: "
        echo "sudo $(which perf) record --freq=max --call-graph=dwarf --timestamp --period --sample-cpu --sample-identifier --data --phys-data --data-page-size --code-page-size --mmap-pages=1024 --inherit --switch-events --output=perf.data -- <...>"
    ;;
    offwake)
        echo "Record off-cpu time and sleep-wakeup pairs:"
        echo "pid=\$(pidof <...>); sudo offwaketime-bpfcc -p \$pid -f > offwake.folded & tracer_pid=\$!; while kill -0 \$pid &>/dev/null; do sleep 1; done; sudo kill -INT \$tracer_pid"
    ;;
    fg)
        if [[ ! -d $HOME/FlameGraph ]]; then 
            git clone https://github.com/brendangregg/FlameGraph $HOME/FlameGraph 
            echo 
        fi 
        echo "Generate per-thread output of perf:"
        echo "sudo chmod a+r \$perf_data_file; perf script --no-inline --force --ns -F +pid -i perf.data > perf.data.perthread"
        
        echo 
        echo "Flamegraph the output of perf:"
        echo "sudo chmod a+r perf.data; perf script --no-inline --force --ns -i perf.data | $HOME/FlameGraph/stackcollapse-perf.pl | $HOME/FlameGraph/stackcollapse-recursive.pl | $HOME/FlameGraph/flamegraph.pl --title=perf.data --subtitle=\"Host: \$(uname -m), Kernel: \$(uname -r), Driver: \$(modinfo nvidia | egrep '^version:' | awk '{print \$2}'), Timestamp: \$(date +'%Y-%m-%d %H:%M:%S')\" --countname='samples' >perf.data.svg"
        
        echo 
        echo "Flamegraph the output of offwaketime-pbfcc:"
        echo "sudo chmod a+r offwake.folded; cat offwake.folded | $HOME/FlameGraph/flamegraph.pl --title=offwake.folded --subtitle=\"Host: $(uname -m), Kernel: $(uname -r), Driver: \$(modinfo nvidia | egrep '^version:' | awk '{print \$2}'), Timestamp: \$(date +'%Y-%m-%d %H:%M:%S')\" --countname='micro-sec off cpu' >offwake.folded.svg"
    ;;
esac 