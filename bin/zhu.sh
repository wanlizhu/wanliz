#!/usr/bin/env bash
trap 'exit 130' INT

subcmd_backup_wsl2_home() {
    if [[ -d /mnt/d/wsl2_home.backup ]]; then
        rsync -ah --ignore-missing-args --delete --info=progress2 \
            $HOME/.bashrc \
            $HOME/.vimrc \
            $HOME/.screenrc \
            $HOME/.gitconfig \
            $HOME/.p4ignore \
            $HOME/.p4tickets \
            $HOME/.nv-tokens.yml \
            $HOME/.cursor/mcp.json \
            $HOME/.ssh \
            $HOME/.cursor \
            $HOME/wanliz \
            /mnt/d/wsl2_home.backup/
    else
        echo "/mnt/d/wsl2_home.backup/ doesn't exist"
    fi
}

subcmd_wanliz_git() {
    if [[ -z "$(git config --global --get user.name)" ]]; then
        git config --global user.name "Wanli Zhu"
        git config --global user.email zhu.wanli@icloud.com
    fi
    if [[ -z $(cat $HOME/wanliz/.git/config | grep "wanlizhu/wanliz" | grep "@") ]]; then 
        read -r -s -p "Decode Password: " passwd
        token=$(echo 'U2FsdGVkX1/56ViCg37yZ/tFFpvGWW+3fYiKVCMeOiFfFrrQIhyg5ju0VUua8hAH8e7UKHbqYyJzJKvoz1opgg==' | openssl enc -d -aes-256-cbc -salt -pbkdf2 -a -k $passwd)
        sed -i "s#https://github.com#https://wanlizhu:${token}@github.com#g" $HOME/wanliz/.git/config
    fi 
    if [[ $1 == pull ]]; then 
        if [[ -d $HOME/wanliz ]]; then
            pushd $HOME/wanliz >/dev/null
            git add .
            git commit -m "$(date)"
            git pull
            popd >/dev/null
        else
            echo "$HOME/wanliz doesn't exist"
        fi
    elif [[ $1 == push ]]; then
        if [[ -d $HOME/wanliz ]]; then
            pushd $HOME/wanliz >/dev/null
            git add .
            git commit -m "$(date)"
            git pull
            git push
            popd >/dev/null
        else
            echo "$HOME/wanliz doesn't exist"
        fi
    fi 
}

subcmd_env() {
    export P4PORT=p4proxy-sc.nvidia.com:2006
    export P4USER=wanliz
    export P4CLIENT=wanliz_sw_linux
    export P4ROOT=/home/wanliz/sw
    export P4IGNORE=$HOME/.p4ignore
    export NVM_GTLAPI_TOKEN='eyJhbGciOiJIUzI1NiJ9.eyJpZCI6IjNlMGZkYWU4LWM5YmUtNDgwOS1iMTQ3LTJiN2UxNDAwOTAwMyIsInNlY3JldCI6IndEUU1uMUdyT1RaY0Z0aHFXUThQT2RiS3lGZ0t5NUpaalU3QWFweUxGSmM9In0.Iad8z1fcSjA6P7SHIluppA_tYzOGxGv4koMyNawvERQ'                                      export GDK_SCALE=1                                                                         
    if [[ -d /mnt/c/Users ]]; then 
        export P4CLIENT=wanliz_sw_windows_wsl2
        export GDK_SCALE=1                                                                      
        export GDK_DPI_SCALE=1.25                                                               
        export QT_SCALE_FACTOR=1.25   
    fi 
}

subcmd_env_umd() {
    export LD_LIBRARY_PATH=$HOME/NVIDIA-Linux-UMD-override${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH} 
    export VK_ICD_FILENAMES=$HOME/NVIDIA-Linux-UMD-override/nvidia_icd.json
}

subcmd_env_pushbuf() {
    subcmd_env_umd
    export __GL_ac12fedf=./pushbuffer-dump-%03d.xml 
    export __GL_ac12fede=0x10183
}

subcmd_encrypt() {
    read -p "Password: " passwd
    echo "$1" | openssl enc -aes-256-cbc -salt -pbkdf2 -a -k $passwd
}

subcmd_decrypt() {
    read -p "Password: " passwd
    echo "$1" | openssl enc -d -aes-256-cbc -salt -pbkdf2 -a -k $passwd
}

case $1 in 
    wsl2backup) subcmd_backup_wsl2_home ;;
    pl)  subcmd_wanliz_git pull ;;
    ps)  subcmd_wanliz_git push ;;
    env) subcmd_env; shift; $@ ;;
    env-umd)     subcmd_env_umd; shift; $@ ;;
    env-pushbuf) subcmd_env_pushbuf; shift; $@ ;;
    encrypt) subcmd_encrypt "$2" ;;
    decrypt) subcmd_decrypt "$2" ;;
esac 