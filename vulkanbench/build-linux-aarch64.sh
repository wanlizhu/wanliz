#!/bin/bash 

if [[ $(uname -m) == x86_64 ]]; then 
    if ! dpkg --print-foreign-architectures | grep -q "arm64"; then 
        sudo dpkg --add-architecture arm64
        ARM64_SOURCES="/etc/apt/sources.list.d/ubuntu-ports-arm64.sources"
        if [[ ! -f "$ARM64_SOURCES" ]]; then
            sudo tee "$ARM64_SOURCES" > /dev/null <<EOF
Types: deb
URIs: http://ports.ubuntu.com/ubuntu-ports/
Suites: noble noble-updates noble-backports
Components: main restricted universe multiverse
Architectures: arm64
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: http://ports.ubuntu.com/ubuntu-ports/
Suites: noble-security
Components: main restricted universe multiverse
Architectures: arm64
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
EOF
        fi
        MAIN_SOURCES="/etc/apt/sources.list.d/ubuntu.sources"
        if [[ -f "$MAIN_SOURCES" ]] && ! grep -q "Architectures:" "$MAIN_SOURCES"; then
            sudo sed -i '/^Types: deb$/a Architectures: amd64' "$MAIN_SOURCES"
        fi
    fi
    
    pkgs=(cmake pkg-config clang gcc g++ lld libvulkan1 libvulkan-dev libshaderc-dev libspirv-cross-c-shared-dev vulkan-tools vulkan-utility-libraries-dev libx11-dev)
    for pkg in "${pkgs[@]}"; do 
        dpkg -s "$pkg" &>/dev/null || sudo apt install -y $pkg  
    done 

    pkgs_arm64=(gcc-aarch64-linux-gnu g++-aarch64-linux-gnu binutils-aarch64-linux-gnu libvulkan1:arm64 libvulkan-dev:arm64 libshaderc-dev:arm64 libspirv-cross-c-shared-dev:arm64 vulkan-tools:arm64 vulkan-utility-libraries-dev:arm64 libx11-dev:arm64)
    for pkg in "${pkgs_arm64[@]}"; do 
        dpkg -s "$pkg" &>/dev/null || sudo apt install -y $pkg  
    done 
fi 

build_dir="build-linux-aarch64"
#rm -rf $build_dir 
mkdir -p $build_dir
cd $build_dir 

if [[ $1 == debug ]]; then 
    echo "Configuring debug build in $(pwd)"
    cmake .. -DCMAKE_TARGET_ARCH=aarch64 -DCMAKE_BUILD_TYPE=Debug || exit 1
else 
    echo "Configuring release build in $(pwd)"
    cmake .. -DCMAKE_TARGET_ARCH=aarch64 -DCMAKE_BUILD_TYPE=Release || exit 1
fi 
cmake --build . || exit 1
echo "Build finished in $(pwd)"

# (optional) for debugging on remote machine
if [[ $2 == tmp ]]; then 
    rm -rf /tmp/wanliz 
    cp -r $HOME/wanliz /tmp/
    cd /tmp/wanliz || exit 1
    rm -rf build-linux-aarch64
    ./vulkanbench/build-linux-aarch64.sh debug || exit 1
fi 