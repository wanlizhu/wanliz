#!/usr/bin/env bash

workspace=$(realpath $(dirname $0))
outdir=$workspace/_out/Linux_$(uname -m | sed 's/x86_64/amd64/g')_release
mkdir -p $outdir 
cd $outdir  
cmake ../.. || exit 1
sudo cmake --build . --target install 