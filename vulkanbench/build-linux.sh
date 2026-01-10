#!/bin/bash 

build_dir="build-linux-$(uname -m)"
if [[ $1 == "--regen-clangd-db" ]]; then 
    build_dir="build-linux-$(uname -m)-temp"
fi 

pkgs=(cmake pkg-config clang gcc g++ build-essential lld libvulkan1 libvulkan1 libvulkan-dev libshaderc-dev libspirv-cross-c-shared-dev vulkan-tools vulkan-utility-libraries-dev libx11-dev binutils)
for pkg in "${pkgs[@]}"; do 
    dpkg -s "$pkg" &>/dev/null || sudo apt install -y $pkg  
done 

#rm -rf $build_dir 
mkdir -p $build_dir
cd $build_dir 

if [[ $1 == debug ]]; then 
    echo "Configuring debug build in $(pwd)"
    cmake ..  -DCMAKE_BUILD_TYPE=Debug || exit 1
else 
    echo "Configuring release build in $(pwd)"
    cmake ..  -DCMAKE_BUILD_TYPE=Release || exit 1
fi 
cmake --build . || exit 1

if [[ $1 == "--regen-clangd-db" ]]; then 
    cp -vf compile_commands.json .. || exit 1
    cd ..
    rm -rf $build_dir
    if [[ -e .clangd ]]; then 
        touch $(readlink -f .clangd)
    fi 
fi 