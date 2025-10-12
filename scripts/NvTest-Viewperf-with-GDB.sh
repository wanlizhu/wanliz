#!/bin/bash

viewset="${1:-maya}"
subtest="${2:-10}"

if [[ -d ~/viewperf2020v3 ]]; then 
    pushd ~/viewperf2020v3
elif [[ -d /mnt/linuxqa/wanliz/viewperf2020v3/$(uname -m) ]]; then 
    pushd /mnt/linuxqa/wanliz/viewperf2020v3/$(uname -m)
else
    echo "Error: folder not found ~/viewperf2020v3"
    exit 1
fi 

[[ -z $(which cgdb) ]] && sudo apt install -y cgdb

gdbenv=()
while IFS='=' read -r k v; do 
    gdbenv+=( -ex "set env $k $v" )
done < <(env | grep -E '^(__GL_|LD_)')

cgdb -- \
    -ex "set trace-commands on" \
    -ex "set pagination off" \
    -ex "set confirm off" \
    -ex "set debuginfod enabled on" \
    -ex "set breakpoint pending on" \
    "${gdbenv[@]}" \
    -ex "file ./viewperf/bin/viewperf" \
    -ex "set args viewsets/$viewset/config/$viewset.xml $subtest -resolution 3840x2160 " \
    -ex "set trace-commands off"

popd >/dev/null 