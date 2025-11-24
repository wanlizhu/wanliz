#!/usr/bin/env bash

remote_ip=$([[ -z $1 ]] && echo "1.1.1.1" || echo $1)
ip -4 route get $(getent ahostsv4 $remote_ip | awk 'NR==1{print $1}') | sed -n 's/.* src \([0-9.]\+\).*/\1/p'