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

sudo dmesg -T | head -n 200 >dmesg_T_200.log 
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



# Build nvbandwidth

wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/sbsa/cuda-ubuntu2404.pin
sudo mv cuda-ubuntu2404.pin /etc/apt/preferences.d/cuda-repository-pin-600
wget https://developer.download.nvidia.com/compute/cuda/13.1.0/local_installers/cuda-repo-ubuntu2404-13-1-local_13.1.0-590.44.01-1_arm64.deb
sudo dpkg -i cuda-repo-ubuntu2404-13-1-local_13.1.0-590.44.01-1_arm64.deb
sudo cp /var/cuda-repo-ubuntu2404-13-1-local/cuda-*-keyring.gpg /usr/share/keyrings/
sudo apt-get update
sudo apt-get -y install cuda-toolkit-13-1

sudo apt install -y libboost-program-options-dev 

```
index   name              compute_cap   persistence_mode   driver_version   GPC_clock   MEM_clock
0       NVIDIA RTX A400   8.6           Enabled            590.44.01        210 MHz     405 MHz
1       NVIDIA GB300      10.3          Enabled            590.44.01        120 MHz     3996 MHz
```

cmake .. -DCMAKE_CUDA_ARCHITECTURES=100 
cmake .. -DCMAKE_CUDA_ARCHITECTURES=86 

```
For RTX GPU:
export __GL_DeviceModalityPreference=2
export CUDA_VISIBLE_DEVICES=1

For B300 GPU:
export __GL_DeviceModalityPreference=1
export CUDA_DEVICE_MODALITY=1
and you may also need to set this, from what I saw in a recent bug report
export CUDA_VISIBLE_DEVICES=0
```

__GL_DeviceModalityPreference=2 CUDA_VISIBLE_DEVICES=1 ./nvbandwidth | tee ~/nvbandwidth-rtxA400-590.44.01-cap86.txt

__GL_DeviceModalityPreference=1 CUDA_DEVICE_MODALITY=1 CUDA_VISIBLE_DEVICES=0 ./nvbandwidth | tee ~/nvbandwidth-gb300-590.44.01-cap100.txt

__GL_DeviceModalityPreference=1 ./nvperf_vulkan -nullDisplay -device 0 texcopy | tee ~/nvperf_vulkan-texcopy-gb300-590.44.01.txt 

__GL_DeviceModalityPreference=1 ./nvperf_vulkan -nullDisplay -device 0 alloc | tee ~/nvperf_vulkan-alloc-gb300-590.44.01.txt 


rsync -ah --progress wanliz@10.221.47.5:/home/wanliz/sw/apps/gpu/drivers/vulkan/microbench/_out/Linux_aarch64_develop/nvperf_vulkan .


# Pull the latest build of nvperf_vulkan
WSL_IP=10.221.33.186
rsync -ah --progress wanliz@$WSL_IP:/home/wanliz/sw/apps/gpu/drivers/vulkan/microbench/_out/Linux_aarch64_develop/nvperf_vulkan $HOME/nvperf_vulkan

# Find the latest build at https://gitlab-master.nvidia.com/perf-inspector/gift/-/releases
# PIC-X 1.4.1: https://gtl-ui.nvidia.com/file/019B32AB-5176-713D-8861-44975F74026B#general
curl -L  https://get.gtl.nvidia.com:443/download/019B32AB-5176-713D-8861-44975F74026B -H "Authorization: Bearer ofCALSfuIVV0iQO8pDDU0Vz3h-uAxriCGASfSucckhg" --output PIC-X_Package_v1.4.1_Linux_L4t_Release.zip

sudo nvidia-smi -pm 1
mkdir -p $HOME/.local/share/vulkan/implicit_layer.d
sudo env DISPLAY=:0 ./SinglePassCapture/pic-x --api=vk --check_clocks=0 --exe="/bin/vkcube"
sudo ./SinglePassCapture/pic-x --api=vk --check_clocks=0 --exe="$HOME/nvperf_vulkan" --arg="-nullDisplay -device 0 texcopy:24" --present=0 --sleep=1 --time=1

# [13:33:52] [info] Command line: /home/nvidia/SinglePassCapture/PerfInspector/Python-venv/bin/python3 /home/nvidia/SinglePassCapture/PerfInspector/processing/processing/pmlsplitter/gen_si_pmlsplit_mods_xml.py -c t254 --view "gfx_extended" --idea_arch t254_single_pass --fs_file /home/nvidia/SinglePassCapture/lnxstress-172_staging/floorsweepingConfig_0.xml
# /home/nvidia/SinglePassCapture/PerfInspector/misc/pmlsplitter/chips/gb20b
# Use the cache PM-Capture config file: /home/nvidia/SinglePassCapture/PerfInspector/exp/t254_gfx_extended


ssh wanliz@dlcluster 
srun -p galaxy_gb300_preprod_pairx2 --pty /bin/bash
srun -p gb300nvl72_preprod --pty /bin/bash 

__GL_DeviceModalityPreference=1 ./vulkaninfo 

