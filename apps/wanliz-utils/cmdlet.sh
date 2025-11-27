#!/usr/bin/env bash

case $1 in 
    rmlog) 
        echo "__GL_DEBUG_MASK=RM __GL_DEBUG_LEVEL=30 __GL_DEBUG_OPTIONS=LOG_TO_FILE __GL_DEBUG_FILENAME=$HOME/RMLogs.txt"
    ;;
esac 