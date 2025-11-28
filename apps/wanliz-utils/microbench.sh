#!/usr/bin/env bash

$HOME/wanliz/apps/inspect-gpu-perf-info/install.sh && 
RMLOG=1 inspect-gpu-perf-info /mnt/linuxqa/wanliz/nvperf_vulkan.$(uname -m) \
    -nullDisplay alloc:27 2>/tmp/microbench.alloc27.rmlog || exit 1
