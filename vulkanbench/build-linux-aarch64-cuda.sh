#!/bin/bash
# This script is intended to run natively on an aarch64 machine (e.g., Jetson)
# Cross-compilation from x86_64 requires CUDA cross-toolchain and proper sysroot

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$SCRIPT_DIR/build-linux-aarch64/cuda"
mkdir -p "$OUT_DIR"

for cu_file in "$SCRIPT_DIR/cuda"/*.cu; do
    name=$(basename "$cu_file" .cu)
    echo "Building $name ..."
    nvcc -O3 -allow-unsupported-compiler -o "$OUT_DIR/$name" "$cu_file" || exit 1
done
