export P4PORT=p4proxy-sc.nvidia.com:2006
export P4USER=wanliz
export P4CLIENT=wanliz_sw_windows_wsl2
export P4ROOT=/home/wanliz/sw
export P4IGNORE=$HOME/.p4ignore
export NVM_GTLAPI_TOKEN='eyJhbGciOiJIUzI1NiJ9.eyJpZCI6IjNlMGZkYWU4LWM5YmUtNDgwOS1iMTQ3LTJiN2UxNDAwOTAwMyIsInNlY3JldCI6IndEUU1uMUdyT1RaY0Z0aHFXUThQT2RiS3lGZ0t5NUpaalU3QWFweUxGSmM9In0.Iad8z1fcSjA6P7SHIluppA_tYzOGxGv4koMyNawvERQ'                                      export GDK_SCALE=1                                                                      
export GDK_DPI_SCALE=1.25                                                               
export QT_SCALE_FACTOR=1.25                                                             
export PATH="$HOME/.local/bin:$HOME/p4v/bin:$PATH"

function backup-wsl2-home() {
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

function pl-git-wanliz() {
    if [[ -d $HOME/wanliz ]]; then
        pushd $HOME/wanliz >/dev/null
        git add .
        git commit -m "$(date)"
        git pull
        popd >/dev/null
    else
        echo "$HOME/wanliz doesn't exist"
    fi
}

function ps-git-wanliz() {
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
}

function pi-upload() {
    if [[ -d $1 ]]; then
        pushd $1 >/dev/null
    elif [[ -d $HOME/SinglePassCapture/PerfInspector/output/$1 ]]; then
        pushd $HOME/SinglePassCapture/PerfInspector/output/$1 >/dev/null
    else
        echo "$1 doesn't exist"
        return 1
    fi
    ./upload_report.sh
    popd >/dev/null
}

function vulkaninfo-grep-section {
    if [[ -z $(which vulkaninfo) && -e $HOME/vulkaninfo ]]; then 
        alias vulkaninfo="$HOME/vulkaninfo"
    fi 
    vulkaninfo 2>/dev/null >/tmp/vulkaninfo
    rm -f /tmp/sections
    cat /tmp/vulkaninfo | grep -B1 -- === | grep -v -- = | grep -i "$1" | sort | uniq >>/tmp/sections
    cat /tmp/vulkaninfo | grep -B1 -- --- | grep -v -- - | grep -i "$1" | sort | uniq >>/tmp/sections
    if [[ $(cat /tmp/sections | wc -l) == 0 ]]; then 
        echo "Find no section title matches $1"
        return 1
    fi 
    for title in $(cat /tmp/sections); do 
        cat /tmp/vulkaninfo | awk -v section_title="$title" '
            $0 ~ section_title { inside_section=1 }
            inside_section && /^[[:space:]]*$/ { exit }
            inside_section { print }
        '
    done 
}

function vulkaninfo-grep-section-memprops() {
    vulkaninfo-grep-section "VkPhysicalDeviceMemoryProperties"
}

