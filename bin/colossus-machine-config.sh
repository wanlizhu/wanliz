sudo su - 
apt update && apt upgrade 
mkdir -p /mnt/linuxqa && mount -t nfs linuxqa.nvidia.com:/storage/people /mnt/linuxqa
/mnt/linuxqa/nvt.sh sync 
/mnt/linuxqa/nvt.sh drivers 580.126.09
/mnt/linuxqa/nvt.sh drivers 591.86

# make sure Xorg is running on nvidia gpu
sudo apt install -y pkg-config
sudo nvidia-xconfig -s -o /etc/X11/xorg.conf --force-generate --mode-debug --layout=Layout0 --render-accel --cool-bits=4 --mode-list=3840x2160 --depth 24 --no-ubb --x-screens-per-gpu=1 --no-separate-x-screens --busid=$(nvidia-xconfig --query-gpu-info | sed -n '/PCI BusID/{{s/^[^:]*:[[:space:]]*//;p;q}}') --connected-monitor=GPU-0.DFP-0 --custom-edid=GPU-0.DFP-0:/mnt/linuxqa/nvtest/pynv_files/edids_db/ASUSPB287_DP_3840x2160x60.000_1151.bin 
sudo screen -S bareX -dm bash -lci "__GL_SYNC_TO_VBLANK=0 X :0 -config /etc/X11/xorg.conf -logfile $HOME/X.log -logverbose 5 -ac +iglx"
export DISPLAY=:1
export __GL_SYNC_TO_VBLANK=0

# use apt-hosted steam 
sudo snap remove steam --purge 
sudo dpkg --add-architecture i386
sudo add-apt-repository multiverse
sudo apt update
sudo apt install steam-installer steam-devices

# install phoronix test suite 
wget https://github.com/phoronix-test-suite/phoronix-test-suite/releases/download/v10.8.4/phoronix-test-suite_10.8.4_all.deb 
sudo apt install -y php-cli php-xml
sudo dpkg -i ./phoronix-test-suite_10.8.4_all.deb

export XDG_SESSION_TYPE=x11
export DESKTOP_SESSION=gnome
export GNOME_SHELL_SESSION_MODE=ubuntu
exec startx
