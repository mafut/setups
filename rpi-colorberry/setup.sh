#!/bin/bash
DIR_COMMON=$(
    cd $(dirname $0)
    cd ../rpi-common/
    pwd
)
source ${DIR_COMMON}/setup64-debian12.sh
apt-get -y install raspberrypi-kernel raspberrypi-kernel-headers

DIR_SELF=$(
    cd $(dirname $0)
    pwd
)
# Display
# https://github.com/hyphenlee/jdi-drm-rpi
# https://github.com/hyphenlee/jdi-drm-rpi/blob/main/jdi-drm-rpi-debian11-32.zip
# https://github.com/hyphenlee/jdi-drm-rpi/blob/main/jdi-drm-rpi-debian12-64-6.6.62%2Brpt-rpi-v8.zip

unzip ${DIR_SELF}/jdi-drm-rpi.zip -d /var/tmp/
cd /var/tmp/jdi-drm-rpi
make install

# Keyboard
# https://github.com/ardangelo/beepberry-keyboard-driver
