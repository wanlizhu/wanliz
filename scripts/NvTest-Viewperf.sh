#!/bin/bash

viewset="${1:-maya}"
subtest="${2:-10}"
profile=$3 

if [[ -d ~/viewperf2020v3 ]]; then 
    pushd ~/viewperf2020v3
elif [[ -d /mnt/linuxqa/wanliz/viewperf2020v3/$(uname -m) ]]; then 
    pushd /mnt/linuxqa/wanliz/viewperf2020v3/$(uname -m)
else
    echo "Error: folder not found ~/viewperf2020v3"
    exit 1
fi 

if [[ $viewset == all ]]; then 
    subtest=
    profile=
    for viewset in catia creo energy maya medical snx sw; do 
        ./viewperf/bin/viewperf viewsets/$viewset/config/$viewset.xml $subtest -resolution 3840x2160 &&
        cat results/${viewset//sw/solidworks}*/results.xml
    done 
else
    if [[ $profile == pi ]]; then 
        read -e -i viewperf-$viewset-$subtest-on-$(hostname) -p "PI report name: " name
        sudo rm -rf $HOME/SinglePassCapture/PerfInspector/output/$name 
        sudo $HOME/SinglePassCapture/pic-x \
            --api=ogl \
            --check_clocks=0 \
            --startframe=100 \
            --name=$name \
            --exe=viewperf/bin/viewperf \
            --arg="viewsets/$viewset/config/$viewset.xml $subtest -resolution 3840x2160" \
            --workdir=$HOME/viewperf2020v3 && {
            read -p "Press [Enter] to upload report: " 
            sudo chown -R $USER:$USER $HOME/SinglePassCapture
            cd $HOME/SinglePassCapture/PerfInspector/output/$name 
            pip install -i https://sc-hw-artf.nvidia.com/artifactory/api/pypi/hwinf-pi-pypi/simple \
                --extra-index-url https://urm.nvidia.com/artifactory/api/pypi/nv-shared-pypi/simple \
                --extra-index-url https://pypi.perflab.nvidia.com pi-uploader &>/dev/null 
            echo | ./upload_report.sh
        }
    else 
        ./viewperf/bin/viewperf viewsets/$viewset/config/$viewset.xml $subtest -resolution 3840x2160 &&
        cat results/${viewset//sw/solidworks}*/results.xml
    fi 
fi 

popd >/dev/null 