sudo apt update && sudo apt upgrade 

sudo su - 
mkdir -p /mnt/linuxqa && mount -t nfs linuxqa.nvidia.com:/storage/people /mnt/linuxqa
/mnt/linuxqa/nvt.sh sync 
/mnt/linuxqa/nvt.sh drivers 580.126.09
/mnt/linuxqa/nvt.sh drivers 591.86

# (optional) install public release driver
sudo tee /etc/modprobe.d/blacklist-nouveau.conf > /dev/null <<'EOF'
blacklist nouveau
options nouveau modeset=0
EOF
sudo modprobe -r nouveau
sudo update-initramfs -u -k all
sudo systemctl stop nvidia-persistenced || sudo nvidia-smi -pm 0
sudo systemctl isolate multi-user 
sudo apt purge -y xserver-xorg-video-nouveau 'nvidia-*' 'libnvidia-*' 'xserver-xorg-video-nvidia-*' 'cuda-*'
sudo apt autoremove -y --purge
sudo apt install -y build-essential pkg-config dkms libglvnd0 libglvnd-dev libglx0 libegl1 
sudo rmmod nvidia_drm nvidia_modeset nvidia_uvm nvidia
sudo ./NVIDIA-Linux-
sudo systemctl isolate graphical 

# headless desktop sharing via RDP
for f in /sys/class/drm/card*-*/status; do 
    printf "%-60s %s\n" "$f" "$(cat "$f" 2>/dev/null)"
done
sudo vim /etc/gdm3/custom.conf # to enable wayland
echo 'options nvidia-drm modeset=1' | sudo tee /etc/modprobe.d/nvidia-kms.conf
sudo update-initramfs -u -k all 
sudo apt install -y gdm3 gnome-remote-desktop
sudo reboot 



# make sure Xorg is running on nvidia gpu
sudo nvidia-xconfig -s -o /etc/X11/xorg.conf --force-generate --mode-debug --layout=Layout0 --render-accel --cool-bits=4 --mode-list=3840x2160 --depth 24 --no-ubb --x-screens-per-gpu=1 --no-separate-x-screens --busid=$(nvidia-xconfig --query-gpu-info | sed -n '/PCI BusID/{{s/^[^:]*:[[:space:]]*//;p;q}}') --connected-monitor=GPU-0.DFP-0 --custom-edid=GPU-0.DFP-0:/mnt/linuxqa/nvtest/pynv_files/edids_db/ASUSPB287_DP_3840x2160x60.000_1151.bin 
sudo screen -S bareX -dm bash -lci "__GL_SYNC_TO_VBLANK=0 X :0 -config /etc/X11/xorg.conf -logfile $HOME/X.log -logverbose 5 -ac +iglx"
export DISPLAY=:1
export __GL_SYNC_TO_VBLANK=0

# use apt-hosted steam 
sudo snap remove steam --purge 
sudo dpkg --add-architecture i386
sudo add-apt-repository multiverse
sudo apt update
sudo apt install steam 

# install phoronix test suite 
wget https://github.com/phoronix-test-suite/phoronix-test-suite/releases/download/v10.8.4/phoronix-test-suite_10.8.4_all.deb 
sudo apt install -y php-cli php-xml
sudo dpkg -i ./phoronix-test-suite_10.8.4_all.deb
phoronix-test-suite benchmark pts/strange-brigade

export XDG_SESSION_TYPE=x11
export DESKTOP_SESSION=gnome
export GNOME_SHELL_SESSION_MODE=ubuntu
exec startx


function gensvg {
    [[ -z $1 ]] && { echo "Invalid Inputs!"; return 1; }
    sudo perf script -i $1 > $1.txt
    sudo $HOME/FlameGraph/stackcollapse-perf.pl $1.txt > $1.txt.folded
    sudo $HOME/FlameGraph/flamegraph.pl $1.txt.folded > $1.svg && echo "Generated $1.svg"
    sudo rm -f $1.txt $1.txt.folded
}

function genperf {
    [[ -z $1 ]] && { echo "Invalid Inputs!"; return 1; }
    sudo perf record -a -F 1000 -m 1024 --mmap-pages 262144 -e cpu-clock --call-graph dwarf,4096 --clockid mono -- sleep 30
    sudo mv perf.data perf.data_cpuclock__pid$1
    gensvg perf.data_cpuclock__pid$1
    sudo perf report -i perf.data_cpuclock__pid$1 -n --call-graph fractal,0.5,callee
}

function genoffcpu {
    [[ -z $1 ]] && { echo "Invalid Inputs!"; return 1; }
    sudo offcputime-bpfcc -f -p $1 30 > offcpu__pid$1.folded
    sudo $HOME/FlameGraph/flamegraph.pl offcpu__pid$1.folded > offcpu__pid$1.svg && echo "Generated offcpu__pid$1.svg"

    sudo perf sched record -a -- sleep 30
    sudo mv perf.data perf.data_sched
    sudo perf sched timehist -i perf.data_sched --pid $1 --cpu-visual --wakeups --state 
    sudo perf sched timehist -i perf.data_sched --pid $1 --summary 
    sudo perf sched latency  -i perf.data_sched --sort avg
}