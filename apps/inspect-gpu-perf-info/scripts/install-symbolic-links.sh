#!/usr/bin/env bash

mkdir -p $(dirname $0)/../_out/Linux_debug
outdir=$(realpath $(dirname $0)/../_out/Linux_debug)
cd $outdir || exit 1
cmake ../.. || exit 1
sudo cmake --build . --config debug || exit 1
sudo ln -sfv $outdir/inspect-gpu-perf-info /usr/local/bin/inspect-gpu-perf-info || exit 1
sudo ln -sfv $outdir/VK_LAYER_igpi_helper.json /usr/share/vulkan/explicit_layer.d/VK_LAYER_igpi_helper.json || exit 1

$(realpath $(dirname $0))/install-gpu-pages-inspector.sh 