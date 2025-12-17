#!/usr/bin/env bash
trap 'exit 130' INT

echo "Are you sure this is DGX spark?"
read -p "Press [Enter] to continue: "

sudo nvidia-smi -pm 1
sudo nvidia-persistenced

if [[ $(uname -m) == "aarch64" ]]; then 
    sudo cp -vf /mnt/linuxqa/wlueking/n1x-bringup/environ_vars /root/nvt/environ_vars || true

    if [[ ! -f /opt/nvidia/update.sh ]]; then 
        read -p "Install spark OTA driver? [Y/n]: " ans
        if [[ -z $ans || $ans == y ]]; then 
            echo "Download spark OTA setup script"
            curl -kL https://nv/spark-eng/eng.sh | sudo bash  || true
            sudo /opt/nvidia/update.sh  || true
            echo "[install new driver if OTA script failed to do so]"
        fi 
    fi

    driver_path=$([[ -f ~/.driver ]] && cat ~/.driver || echo "")
    tests_tarball=
    if [[ -e ${driver_path/-internal.run/-tests.tar} ]]; then 
        tests_tarball=${driver_path/-internal.run/-tests.tar}
    elif [[ -e $(dirname $driver_path)/tests-Linux-$(uname -m).tar ]]; then 
        tests_tarball=$(dirname $driver_path)/tests-Linux-$(uname -m).tar
    fi 

    if [[ -z $tests_tarball ]]; then 
        read -rp "Location of tests-Linux-$(uname -m).tar: " tests_tarball
    fi 

    if [[ -f $tests_tarball ]]; then 
        sudo rm -rf /tmp/tests-Linux-$(uname -m)
        tar -xf $tests_tarball -C /tmp
        cp -f /tmp/tests-Linux-$(uname -m)/sandbag-tool/sandbag-tool ~
        cp -f /tmp/tests-Linux-$(uname -m)/LockToRatedTdp/LockToRatedTdp ~
    fi 

    cd ~
    sudo chmod +x ./sandbag-tool ./LockToRatedTdp
    sudo ./sandbag-tool -unsandbag && echo "Unsandbag - [OK]" || echo "Unsandbag - [FAILED]"
    sudo ./LockToRatedTdp -lock && echo "LockToRatedTdp - [OK]" || echo "LockToRatedTdp - [FAILED]"
fi 

cd ~

if [[ $(uname -m) == "aarch64" ]]; then 
    cp -vf /mnt/linuxqa/wanliz/perfdebug.aarch64 ~/perfdebug
    sudo chmod +x ./perfdebug  
    sudo ./perfdebug --lock_loose  set pstateId P0         && echo "set pstateId P0 [OK]" || echo "set pstateId P0 [OK]"
    sudo ./perfdebug --lock_strict set dramclkkHz  4266000 && echo "set dramclkkHz  4266000 - [OK]" || echo "set dramclkkHz  4266000 - [FAILED]"
    sudo ./perfdebug --lock_strict set gpcclkkHz   2000000 && echo "set gpcclkkHz   2000000 - [OK]" || echo "set gpcclkkHz   2000000 - [FAILED]"
    sudo ./perfdebug --lock_loose  set xbarclkkHz  1800000 && echo "set xbarclkkHz  1800000 - [OK]" || echo "set xbarclkkHz  1800000 - [FAILED]"
    sudo ./perfdebug --lock_loose  set sysclkkHz   1800000 && echo "set sysclkkHz   1800000 - [OK]" || echo "set sysclkkHz   1800000 - [FAILED]"
    sudo ./perfdebug --force_regime ffr  
    sudo ./perfdebug --getclocks 
elif [[ $(uname -m) == "x86_64" ]]; then 
    cp -vf /mnt/linuxqa/wanliz/perfdebug.x86_64 ~/perfdebug
    sudo chmod +x ./perfdebug 
    sudo ./perfdebug --lock_loose  set pstateId P0         && echo "set pstateId P0 [OK]" || echo "set pstateId P0 [OK]"
    sudo ./perfdebug --lock_strict set dramclkkHz  8000000 && echo "set dramclkkHz  8000000 - [OK]" || echo "set dramclkkHz  8000000 - [FAILED]"
    sudo ./perfdebug --lock_strict set gpcclkkHz   1875000 && echo "set gpcclkkHz   1875000 - [OK]" || echo "set gpcclkkHz   1875000 - [FAILED]"
    sudo ./perfdebug --lock_loose  set xbarclkkHz  2250000 && echo "set xbarclkkHz  2250000 - [OK]" || echo "set xbarclkkHz  2250000 - [FAILED]"
    sudo ./perfdebug --lock_loose  set sysclkkHz   1695000 && echo "set sysclkkHz   1695000 - [OK]" || echo "set sysclkkHz   1695000 - [FAILED]"
    sudo ./perfdebug --force_regime ffr  
    sudo ./perfdebug --getclocks 
fi 