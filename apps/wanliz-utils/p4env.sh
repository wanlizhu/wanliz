#!/usr/bin/env bash

export P4PORT="p4proxy-sc.nvidia.com:2006"
export P4USER="wanliz"
export P4CLIENT="wanliz_sw_linux"
export P4ROOT="/wanliz_sw_linux"
export P4IGNORE="$HOME/.p4ignore"

if [[ ! -f ~/.p4ignore ]]; then 
    cat >~/.p4ignore <<EOF
_out
_doc
.git
.vscode
.cursorignore
.clangd
.p4config
.p4ignore
compile-commands.json
*.code-workspace
EOF
fi 

if [[ -z $(which p4) ]]; then
    sudo cp -f /mnt/d/wanliz/apps/bin/$(uname -m)/p4 /usr/local/bin/
fi 

if ! p4 login -s &>/dev/null; then 
    p4 login 
fi 

if [[ $1 == "-print" ]]; then 
    echo "export P4PORT=$P4PORT; export P4USER=$P4USER; export P4CLIENT=$P4CLIENT; export P4ROOT=$P4ROOT; export P4IGNORE=$P4IGNORE"
else
    exec bash -i
fi 