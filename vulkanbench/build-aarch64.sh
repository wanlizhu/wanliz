#!/bin/bash 

rm -rf build-aarch64
mkdir -p build-aarch64 
cd build-aarch64 
cmake .. -DCMAKE_TARGET_ARCH=aarch64 -DCMAKE_BUILD_TYPE=Release
cmake --build .