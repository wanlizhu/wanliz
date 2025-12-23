#!/usr/bin/env bash
trap 'exit 130' INT

# wanliz-nvmake-install wanliz@10.221.15.91 opengl aarch64 develop 590.51 
export __GL_DeviceModalityPreference=1
WSL_IP=10.221.47.8
DEV_ID=0
cd $HOME 

if [[ ! -f nvperf_vulkan ]]; then 
    rsync -ah --progress wanliz@$WSL_IP:/wanliz_sw_windows_wsl2/apps/gpu/drivers/vulkan/microbench/_out/Linux_aarch64_develop/nvperf_vulkan . 
fi 

./nvperf_vulkan -nullDisplay -device 0 texcopy &>nvperf_vulkan__gb300__texcopy.log
./nvperf_vulkan -nullDisplay -device 0 texcopy:24 -v &>nvperf_vulkan__gb300__texcopy24_verbose.log

WANLIZ_PRINTF=1 WANLIZ_PRINT=info ./nvperf_vulkan -nullDisplay -device 0 texcopy:24 -v &>nvperf_vulkan__gb300__texcopy24_verbose_wanlizPrintf.log
WANLIZ_REGKEY=1 ./nvperf_vulkan -nullDisplay -device 0 texcopy:24 -v &>nvperf_vulkan__gb300__texcopy24_verbose_wanlizRegKey.log

__GL_DEBUG_LEVEL=30 __GL_DEBUG_MASK=RM ./nvperf_vulkan -nullDisplay -device 0 alloc:27 2>nvperf_vulkan__gb300__alloc27_RM_calls_stdio.log
__GL_DEBUG_LEVEL=30 __GL_DEBUG_MASK=RM ./nvperf_vulkan -nullDisplay -device 0 texcopy:24 2>nvperf_vulkan__gb300__texcopy24_RM_calls_stdio.log

#__GL_DEBUG_MASK=PUSHBUFFER __GL_DEBUG_LEVEL=50   __GL_DEBUG_OPTIONS="LOG_TO_CONSOLE:PRINT_THREAD_ID:PRINT_INDENT:FLUSHFILE_PER_WRITE" ./nvperf_vulkan -nullDisplay -device 0 texcopy:24 2>nvperf_vulkan__gb300__texcopy24_pushbuffer_stdio.log 
rm -f nvperf_vulkan__gb300__texcopy24_pushbuffer_frame* && __GL_ac12fedf=./nvperf_vulkan__gb300__texcopy24_pushbuffer_frame%03d.xml __GL_ac12fede=0x10183 ./nvperf_vulkan -nullDisplay -device 0 texcopy:24

__GL_DEBUG_MASK=PERFSTRAT __GL_DEBUG_LEVEL=100 __GL_DEBUG_OPTIONS="LOG_TO_CONSOLE:PRINT_THREAD_ID:PRINT_INDENT:FLUSHFILE_PER_WRITE" ./nvperf_vulkan -nullDisplay -device 0 texcopy:24 2>nvperf_vulkan__gb300__texcopy24_perfstrat_stdio.log 

__GL_DEBUG_MASK=CYCLESTATS __GL_DEBUG_LEVEL=20 __GL_DEBUG_OPTIONS="LOG_TO_CONSOLE:PRINT_THREAD_ID:PRINT_INDENT:FLUSHFILE_PER_WRITE" ./nvperf_vulkan -nullDisplay -device 0 texcopy:24 2>nvperf_vulkan__gb300__texcopy24_cyclestats_stdio.log 

__GL_DEBUG_MASK=VK_ERROR __GL_DEBUG_LEVEL=20 __GL_DEBUG_OPTIONS="LOG_TO_CONSOLE:PRINT_THREAD_ID:PRINT_INDENT:FLUSHFILE_PER_WRITE" ./nvperf_vulkan -nullDisplay -device 0 texcopy:24 2>nvperf_vulkan__gb300__texcopy24_vk_error_stdio.log 

__GL_DEBUG_MASK=VK_SYNC __GL_DEBUG_LEVEL=20 __GL_DEBUG_OPTIONS="LOG_TO_CONSOLE:PRINT_THREAD_ID:PRINT_INDENT:FLUSHFILE_PER_WRITE" ./nvperf_vulkan -nullDisplay -device 0 texcopy:24 2>nvperf_vulkan__gb300__texcopy24_vk_sync_stdio.log 

NAME=nvperf_vulkan__gb300__alloc27_perf FREQ=10000 perf-record-gb300 ./nvperf_vulkan -nullDisplay -device 0 alloc:27

sudo dmesg -T | head -n 200 >boot_params.log 
ls -l /boot/config-$(uname -r) 2>/dev/null >kernel_config.log 
ulimit -a >ulimit_a.log 
cat /proc/cpuinfo >cpuinfo.log
numactl -H 2>/dev/null >numactl_H.log 
numastat -m 2>/dev/null >numastat_m.log 
cat /proc/meminfo >meminfo.log 
cat /proc/vmstat | head -n 200 >vmstat.log 
sysctl -a 2>/dev/null >sysctl_a.log 
modinfo nvidia 2>/dev/null >modinfo_nvidia.log
modinfo nvidia_uvm 2>/dev/null >modinfo_nvidia_uvm.log
modinfo nvidia_drm 2>/dev/null >modinfo_nvidia_drm.log 
modinfo nvidia_modeset 2>/dev/null >modinfo_nvidia_modeset.log 
bash -c 'for m in nvidia nvidia_uvm nvidia_drm nvidia_modeset nvidia_peermem; do echo "=== modinfo -p $m ==="; modinfo -p "$m" 2>/dev/null || true; done' >modinfo_params.log 
bash -c 'for m in nvidia nvidia_uvm nvidia_drm nvidia_modeset nvidia_peermem; do d="/sys/module/$m/parameters"; echo "=== $d ==="; if [ -d "$d" ]; then (cd "$d" && ls -1 | while read -r p; do printf "%s=" "$p"; cat "$p" 2>/dev/null || true; echo; done); fi; done' >sysfs_module_params.log 
bash -c 'ls -R /proc/driver/nvidia 2>/dev/null || true; cat /proc/driver/nvidia/version 2>/dev/null || true; cat /proc/driver/nvidia/params 2>/dev/null || true; for f in /proc/driver/nvidia/gpus/*/information /proc/driver/nvidia/gpus/*/power /proc/driver/nvidia/gpus/*/registry; do [ -e "$f" ] && { echo "=== $f ==="; cat "$f"; echo; }; done' >proc_driver_nvidia.log 
sudo dmesg -T | egrep -i "nvrm|nvidia|uvm|nvlink|fabric|pcie|iommu|gsp|xid" >dmesg_nvidia.log 
nvidia-smi -q -x >nvidia-smi_q_x.xml 
nvidia-smi topo -m >nvidia-smi_topo_m.log 
nvidia-smi topo -p2p n >nvidia-smi_topo_p2p_n.log 
bash -c 'ls -la /etc/vulkan 2>/dev/null || true; find /etc/vulkan -maxdepth 3 -type f -print -exec sed -n "1,200p" {} \; 2>/dev/null || true; ls -la /usr/share/vulkan 2>/dev/null || true; find /usr/share/vulkan -maxdepth 3 -type f -name "*.json" -print -exec sed -n "1,200p" {} \; 2>/dev/null || true' >vulkan_icd_layers.log 
env | sort >env.log 
vulkaninfo --summary >vulkaninfo_summary.log 
vulkaninfo >vulkaninfo.log 


__GL_DeviceModalityPreference=0 ./nvperf_vulkan -nullDisplay -device 0 texcopy &>nvperf_vulkan__rtxA400__texcopy.log
__GL_DeviceModalityPreference=0 ./nvperf_vulkan -nullDisplay -device 0 texcopy:24 -v &>nvperf_vulkan__rtxA400__texcopy24_verbose.log

__GL_DeviceModalityPreference=0 WANLIZ_PRINTF=1 WANLIZ_PRINT=info ./nvperf_vulkan -nullDisplay -device 0 texcopy:24 -v &>nvperf_vulkan__rtxA400__texcopy24_verbose_wanlizPrintf.log
__GL_DeviceModalityPreference=0 WANLIZ_REGKEY=1 ./nvperf_vulkan -nullDisplay -device 0 texcopy:24 -v &>nvperf_vulkan__rtxA400__texcopy24_verbose_wanlizRegKey.log

__GL_DeviceModalityPreference=0 __GL_DEBUG_LEVEL=30 __GL_DEBUG_MASK=RM ./nvperf_vulkan -nullDisplay -device 0 alloc:27 2>nvperf_vulkan__rtxA400__alloc27_RM_calls_stdio.log
__GL_DeviceModalityPreference=0 __GL_DEBUG_LEVEL=30 __GL_DEBUG_MASK=RM ./nvperf_vulkan -nullDisplay -device 0 texcopy:24 2>nvperf_vulkan__rtxA400__texcopy24_RM_calls_stdio.log

#__GL_DEBUG_MASK=PUSHBUFFER __GL_DEBUG_LEVEL=50   __GL_DEBUG_OPTIONS="LOG_TO_CONSOLE:PRINT_THREAD_ID:PRINT_INDENT:FLUSHFILE_PER_WRITE" ./nvperf_vulkan -nullDisplay -device 0 texcopy:24 2>nvperf_vulkan__rtxA400__texcopy24_pushbuffer_stdio.log 
rm -f nvperf_vulkan__rtxA400__texcopy24_pushbuffer_frame* && __GL_DeviceModalityPreference=0  __GL_ac12fedf=./nvperf_vulkan__rtxA400__texcopy24_pushbuffer_frame%03d.xml __GL_ac12fede=0x10183 ./nvperf_vulkan -nullDisplay -device 0 texcopy:24

__GL_DeviceModalityPreference=0 __GL_DEBUG_MASK=PERFSTRAT __GL_DEBUG_LEVEL=100 __GL_DEBUG_OPTIONS="LOG_TO_CONSOLE:PRINT_THREAD_ID:PRINT_INDENT:FLUSHFILE_PER_WRITE" ./nvperf_vulkan -nullDisplay -device 0 texcopy:24 2>nvperf_vulkan__rtxA400__texcopy24_perfstrat_stdio.log 

__GL_DeviceModalityPreference=0 __GL_DEBUG_MASK=CYCLESTATS __GL_DEBUG_LEVEL=20 __GL_DEBUG_OPTIONS="LOG_TO_CONSOLE:PRINT_THREAD_ID:PRINT_INDENT:FLUSHFILE_PER_WRITE" ./nvperf_vulkan -nullDisplay -device 0 texcopy:24 2>nvperf_vulkan__rtxA400__texcopy24_cyclestats_stdio.log 

__GL_DeviceModalityPreference=0 __GL_DEBUG_MASK=VK_ERROR __GL_DEBUG_LEVEL=20 __GL_DEBUG_OPTIONS="LOG_TO_CONSOLE:PRINT_THREAD_ID:PRINT_INDENT:FLUSHFILE_PER_WRITE" ./nvperf_vulkan -nullDisplay -device 0 texcopy:24 2>nvperf_vulkan__rtxA400__texcopy24_vk_error_stdio.log 

__GL_DeviceModalityPreference=0 __GL_DEBUG_MASK=VK_SYNC __GL_DEBUG_LEVEL=20 __GL_DEBUG_OPTIONS="LOG_TO_CONSOLE:PRINT_THREAD_ID:PRINT_INDENT:FLUSHFILE_PER_WRITE" ./nvperf_vulkan -nullDisplay -device 0 texcopy:24 2>nvperf_vulkan__rtxA400__texcopy24_vk_sync_stdio.log 

NAME=nvperf_vulkan__rtxA400__alloc27_perf FREQ=10000 perf-record ./nvperf_vulkan -nullDisplay -device 0 alloc:27