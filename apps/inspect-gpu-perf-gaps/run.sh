#!/usr/bin/env bash

workspace=$(cd $(dirname ${BASH_SOURCE[0]})/.. && pwd)
outdir=$workspace/_out/Linux_$(uname -m | sed 's/x86_64/amd64/g')_debug
mkdir -p $outdir 
cd $outdir || exit 1
cmake ../.. || exit 1
./inspect-gpu-perf-gaps
