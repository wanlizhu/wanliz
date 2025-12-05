#!/usr/bin/env bash

cd $HOME/wanliz/apps/inspect-gpu-perf-info
mkdir -p _out/Linux_debug
cd _out/Linux_debug  
cmake ../.. || exit 1
sudo cmake --build . --config debug || exit 1
sudo ln -sfv $(pwd)/inspect-gpu-perf-info /usr/local/bin/inspect-gpu-perf-info || exit 1
sudo ln -sfv $(pwd)/VK_LAYER_igpi_helper.json /usr/share/vulkan/explicit_layer.d/VK_LAYER_igpi_helper.json || exit 1
