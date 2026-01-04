#!/bin/bash 

HOST_ARCH=$(dpkg --print-architecture)
if [[ "$HOST_ARCH" != "amd64" ]]; then
    echo "Need to build on amd64 hosts"
    exit 1
fi

PACKAGES="cmake pkg-config clang gcc g++ lld libvulkan1 libvulkan-dev libshaderc-dev libspirv-cross-c-shared-dev vulkan-tools vulkan-utility-libraries-dev libx11-dev"

PACKAGES_ARM64="gcc-aarch64-linux-gnu g++-aarch64-linux-gnu binutils-aarch64-linux-gnu libvulkan1:arm64 libvulkan-dev:arm64 libshaderc-dev:arm64 libspirv-cross-c-shared-dev:arm64 vulkan-tools:arm64 vulkan-utility-libraries-dev:arm64 libx11-dev:arm64"

if ! dpkg --print-foreign-architectures | grep -q "arm64"; then 
    sudo dpkg --add-architecture arm64
fi

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

sudo apt update
sudo apt install -y $PACKAGES
sudo apt install -y $PACKAGES_ARM64

