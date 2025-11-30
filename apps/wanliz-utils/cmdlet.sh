#!/usr/bin/env bash

case $1 in 
    rmlog) 
        echo "__GL_DEBUG_MASK=RM __GL_DEBUG_LEVEL=30 __GL_DEBUG_OPTIONS=LOG_TO_FILE __GL_DEBUG_FILENAME=$HOME/RMLogs.txt"
    ;;
    clamp)
        echo " | awk '/AAAA/{flag=1; next} /ZZZZ/{flag=0} flag'"
    ;;
    nsight)
        echo "Install Nsight  systems: https://urm.nvidia.com/artifactory/swdt-nsys-generic/ctk/"
        echo "Install Nsight graphics: https://ngfx/builds-prerel/Grxa/"
        echo "Install Nsight graphics: https://ngfx/builds-nightly/Grfx/"
        echo "Install Nsight graphics: \\devrel\share\Devtools\NomadBuilds\latest\Internal (username is email)"
    ;;
esac 