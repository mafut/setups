#!/bin/bash
DIR_COMMON=$(
    cd $(dirname $0)
    cd ../rpi-common/
    pwd
)
source ${DIR_COMMON}/setup-debian12.sh
