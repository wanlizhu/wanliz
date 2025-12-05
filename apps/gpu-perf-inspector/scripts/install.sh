#!/usr/bin/env bash

cd $HOME/wanliz/apps/gpu-perf-inspector || exit 1
mkdir -p _out/Linux_debug
cd _out/Linux_debug  
cmake ../.. || exit 1
sudo cmake --build . --config debug || exit 1
sudo ln -sfv $(pwd)/gpu-perf-inspector /usr/local/bin/gpu-perf-inspector || exit 1
sudo ln -sfv $(pwd)/VK_LAYER_gpu_perf_inspector.json /usr/share/vulkan/explicit_layer.d/VK_LAYER_gpu_perf_inspector.json || exit 1
