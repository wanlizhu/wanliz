#!/bin/bash 

pkgs=(cmake pkg-config clang gcc g++ build-essential lld libvulkan1 libvulkan1 libvulkan-dev libshaderc-dev libspirv-cross-c-shared-dev vulkan-tools vulkan-utility-libraries-dev libx11-dev binutils)
for pkg in "${pkgs[@]}"; do 
    dpkg -s "$pkg" &>/dev/null || sudo apt install -y $pkg  
done 

build_dir="build-linux-$(uname -m)"
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

# (optional) for debugging on remote machine
if [[ $2 == tmp ]]; then 
    rm -rf /tmp/wanliz 
    cp -r $HOME/wanliz /tmp/
    cd /tmp/wanliz || exit 1
    rm -rf build-linux
    ./vulkanbench/build-linux.sh debug || exit 1
fi 