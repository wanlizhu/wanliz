#!/bin/bash

build_dir=build-linux-$(uname -m)/cuda
mkdir -p $build_dir

for cu_file in ./vulkanbench/cuda/*.cu; do
    name=$(basename $cu_file .cu)
    echo "Building $name ..."
    nvcc -O3 -allow-unsupported-compiler -o $build_dir/$name $cu_file || exit 1
done
