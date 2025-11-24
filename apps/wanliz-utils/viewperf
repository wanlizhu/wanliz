#!/usr/bin/env bash

if [[ -z $DISPLAY ]]; then 
    export DISPLAY=:0
    echo "Fallback to DISPLAY=$DISPLAY"
fi 

if [[ ! -d ~/viewperf2020v3 ]]; then
    rsync -ah --info=progress2 /mnt/linuxqa/wanliz/viewperf2020v3.$(uname -m)/ ~/viewperf2020v3 || exit 1
fi 

declare -A viewset_names=(
    ["catia"]="catia-06"
    ["creo"]="creo-03"
    ["energy"]="energy-03"
    ["maya"]="maya-06"
    ["medical"]="medical-03"
    ["snx"]="snx-04"
    ["sw"]="solidworks-07"
)
viewsets=
subtest=

while [[ ! -z $1 ]]; do 
    case $1 in 
        catia|creo|energy|maya|medical|snx|sw) viewsets+=" $1" ;;
        [0-9]*) subtest=$1 ;;
        -memlog) 
            export __GL_DEBUG_MASK=RM
            export __GL_DEBUG_LEVEL=30
            export __GL_DEBUG_OPTIONS=LOG_TO_FILE 
            export __GL_DEBUG_FILENAME=$HOME/viewperf.memlog.txt
            echo "Log to file $__GL_DEBUG_FILENAME"
        ;;
        *) echo "Unknown option: $1" ;;
    esac
    shift 
done 

if [[ -z $viewsets ]]; then 
    viewsets="catia creo energy maya medical snx sw"
    rm -rf $HOME/viewperf2020v3/results
    mkdir -p $HOME/viewperf2020v3/results
fi 

cd $HOME/viewperf2020v3 || exit 1

for viewset in $viewsets; do 
    $HOME/viewperf2020v3/viewperf/bin/viewperf viewsets/$viewset/config/$viewset.xml $subtest -resolution 3840x2160 && {
        results_xml=$HOME/viewperf2020v3/results/${viewset_names[$viewset]}/results.xml
        composite_score=$(cat $results_xml | grep "Composite" | awk -F'"' '{print $2}')
        echo -e "$viewset\t$composite_score"
    } 
done 