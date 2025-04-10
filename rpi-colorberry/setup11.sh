#!/bin/bash
DIR_COMMON=$(
    cd $(dirname $0)
    cd ../rpi-common/
    pwd
)

apt-get -y install raspberrypi-kernel raspberrypi-kernel-headers

source ${DIR_COMMON}/setup.sh

# Display
# https://github.com/hyphenlee/jdi-drm-rpi
unzip ${DIR_SELF}/jdi-drm-rpi-debian11-32.zip -d /var/tmp/
cd /var/tmp/jdi-drm-rpi
make install

# Keyboard
# https://github.com/ardangelo/beepberry-keyboard-driver
