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
    vulkaninfo 2>/dev/null | grep -B1 -- --- | grep -v -- - | grep -i $1 >/tmp/sections
    if [[ $(cat /tmp/sections | wc -l) == 0 ]]; then 
        echo "Find no section title matches $1"
        return 1
    fi 
    for title in $(cat /tmp/sections); do 
        vulkaninfo 2>/dev/null | awk -v section_title="$title" '
            $0 ~ section_title { inside_section=1 }
            inside_section && /^[[:space:]]*$/ { exit }
            inside_section { print }
        '
    done 
}