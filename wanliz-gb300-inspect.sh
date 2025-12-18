#!/usr/bin/env bash
trap 'exit 130' INT

# wanliz-install-driver wanliz@10.221.15.91 opengl aarch64 develop 590.51 
export __GL_DeviceModalityPreference=1
WSL_IP=10.221.15.91
DEV_ID=0
cd $HOME 

if [[ ! -f nvperf_vulkan ]]; then 
    rsync -ah --progress wanliz@$WSL_IP:/wanliz_sw_windows_wsl2/apps/gpu/drivers/vulkan/microbench/_out/Linux_aarch64_develop/nvperf_vulkan . 
fi 

__GL_DEBUG_LEVEL=30 __GL_DEBUG_MASK=RM ./nvperf_vulkan -nullDisplay -device $DEV_ID alloc:27 2>nvperf_vulkan__alloc27_RM_calls_stdio.log

__GL_DEBUG_LEVEL=30 __GL_DEBUG_MASK=RM ./nvperf_vulkan -nullDisplay -device 0 texcopy:24 2>nvperf_vulkan__texcopy24_RM_calls_stdio.log

__GL_DEBUG_MASK=PUSHBUFFER __GL_DEBUG_LEVEL=50   __GL_DEBUG_OPTIONS="LOG_TO_CONSOLE:PRINT_THREAD_ID:PRINT_INDENT:FLUSHFILE_PER_WRITE" ./nvperf_vulkan -nullDisplay -device 0 texcopy:24 2>nvperf_vulkan__texcopy24_pushbuffer_stdio.log 

__GL_DEBUG_MASK=PERFSTRAT __GL_DEBUG_LEVEL=100 __GL_DEBUG_OPTIONS="LOG_TO_CONSOLE:PRINT_THREAD_ID:PRINT_INDENT:FLUSHFILE_PER_WRITE" ./nvperf_vulkan -nullDisplay -device 0 texcopy:24 2>nvperf_vulkan__texcopy24_perfstrat_stdio.log 

__GL_DEBUG_MASK=CYCLESTATS __GL_DEBUG_LEVEL=20 __GL_DEBUG_OPTIONS="LOG_TO_CONSOLE:PRINT_THREAD_ID:PRINT_INDENT:FLUSHFILE_PER_WRITE" ./nvperf_vulkan -nullDisplay -device 0 texcopy:24 2>nvperf_vulkan__texcopy24_cyclestats_stdio.log 

__GL_DEBUG_MASK=VK_ERROR __GL_DEBUG_LEVEL=20 __GL_DEBUG_OPTIONS="LOG_TO_CONSOLE:PRINT_THREAD_ID:PRINT_INDENT:FLUSHFILE_PER_WRITE" ./nvperf_vulkan -nullDisplay -device 0 texcopy:24 2>nvperf_vulkan__texcopy24_vk_error_stdio.log 

__GL_DEBUG_MASK=VK_SYNC __GL_DEBUG_LEVEL=20 __GL_DEBUG_OPTIONS="LOG_TO_CONSOLE:PRINT_THREAD_ID:PRINT_INDENT:FLUSHFILE_PER_WRITE" ./nvperf_vulkan -nullDisplay -device 0 texcopy:24 2>nvperf_vulkan__texcopy24_vk_sync_stdio.log 