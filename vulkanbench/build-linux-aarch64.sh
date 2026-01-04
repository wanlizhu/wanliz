#!/bin/bash 

build_dir="build-linux-aarch64"
if [[ $1 == "--regen-clangd-db" ]]; then 
    build_dir="build-linux-aarch64-temp"
fi 

rm -rf $build_dir 
mkdir -p $build_dir
cd $build_dir 

cmake .. -DCMAKE_TARGET_ARCH=aarch64 -DCMAKE_BUILD_TYPE=Release || exit 1
cmake --build . || exit 1

if [[ $1 == "--regen-clangd-db" ]]; then 
    cp -vf compile_commands.json .. || exit 1
    cd ..
    rm -rf $build_dir
    if [[ -e .clangd ]]; then 
        touch $(readlink -f .clangd)
    fi 
fi 