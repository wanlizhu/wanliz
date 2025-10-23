
sudo $HOME/nsight_systems/target-linux-sbsa-armv8/nsys profile --run-as=nvidia --sample='system-wide' --event-sample='system-wide'  --stats=true --trace='cuda,nvtx,osrt,opengl' --opengl-gpu-workload=true --start-frame-index=100 --duration-frames=60  --gpu-metrics-devices=all  --gpuctxsw=true --output="viewperf_medical__%h__$(date '+%y%m%d-%H%M')" --force-overwrite=true --env-var='DISPLAY=:0,__GL_SYNC_TO_VBLANK=0,__GL_DEBUG_BYPASS_ASSERT=c' $HOME/viewperf2020v3/viewperf/bin/viewperf viewsets/medical/config/medical.xml -resolution 3840x2160

