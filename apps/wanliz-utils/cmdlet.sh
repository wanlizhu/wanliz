#!/usr/bin/env bash

case $1 in 
    rmlog) 
        echo "__GL_DEBUG_MASK=RM __GL_DEBUG_LEVEL=30 __GL_DEBUG_OPTIONS=LOG_TO_FILE __GL_DEBUG_FILENAME=$HOME/RMLogs.txt"
    ;;
    clamp)
        echo " | awk '/AAAA/{flag=1; next} /ZZZZ/{flag=0} flag'"
    ;;
    nsight)
        echo "Install Nsight  systems: https://urm.nvidia.com/artifactory/swdt-nsys-generic/ctk/"
        echo "Install Nsight graphics: https://ngfx/builds-prerel/Grxa/"
        echo "Install Nsight graphics: https://ngfx/builds-nightly/Grfx/"
        echo "Install Nsight graphics: \\devrel\share\Devtools\NomadBuilds\latest\Internal (username is email)"
        echo 
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
            echo ">> sudo $HOME/nsight_systems/bin/nsys profile --trace=vulkan,opengl,cuda,nvtx,osrt --vulkan-gpu-workload=individual --sample=process-tree --sampling-period=$sampling_period --samples-per-backtrace=1 --backtrace=dwarf --cpuctxsw=process-tree --syscall=process-tree --gpu-metrics-devices=all --gpu-metrics-frequency=$metrics_freq --stats=true --export=sqlite,text --resolve-symbols=true --force-overwrite=true --stop-on-exit=true --wait=all --output=nsys_ --show-output=Nsys_$(hostname)_$(date +%Y%m%d) <exe-and-args>" 
        else
            echo -e "\tError: ~/nsight_systems/bin/nsys doesn't exist"
        fi 
        echo 
        echo "Launch Nsight graphics from command line:"
        echo -e "\tTODO"
    ;;
esac 