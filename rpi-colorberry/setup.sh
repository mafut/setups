#!/bin/bash
DIR_COMMON=$(
    cd $(dirname $0)
    cd ../rpi-common/
    pwd
)

apt-get -y install raspberrypi-kernel-headers i2c-tools

source ${DIR_COMMON}/setup.sh

# Display
# https://github.com/hyphenlee/jdi-drm-rpi
if [ ! -e /boot/overlays/sharp-drm.dtbo ]; then
    unzip ${DIR_SELF}/jdi-drm-rpi-debian11-32.zip -d /var/tmp/ -o
    cd /var/tmp/jdi-drm-rpi
    make install
fi

# Keyboard
# https://github.com/ardangelo/beepberry-keyboard-driver -> didn't work
# https://github.com/sqfmi/bbqX0kbd_driver -> worked
if [ ! -e /boot/overlays/beepy-kbd.dtbo ]; then
    unzip ${DIR_SELF}/beepy-kbd.zip -d /var/tmp/ -o
    cd /var/tmp/bbqX0kbd-driver-main
    make install
fi
rm -f /etc/console-setup/cached_setup_keyboard.sh
dpkg-reconfigure keyboard-configuration

# Backlight
cp -f ${DIR_SELF}/side-button.py /usr/local/sbin/side-button.py
chmod +x /usr/local/sbin/side-button.py
echo "@reboot   sleep 5;/usr/local/sbin/side-button.py" >/var/tmp/crontab.txt
crontab /var/tmp/crontab.txt

cat <<EOF >>${FILE_BASHALIASES}
alias d0="echo 0 | sudo tee /sys/module/sharp_drm/parameters/dither"
alias d1="echo 1 | sudo tee /sys/module/sharp_drm/parameters/dither"
alias d2="echo 2 | sudo tee /sys/module/sharp_drm/parameters/dither"
alias d3="echo 3 | sudo tee /sys/module/sharp_drm/parameters/dither"
alias d4="echo 4 | sudo tee /sys/module/sharp_drm/parameters/dither"
alias by="echo 1 | sudo tee /sys/module/sharp_drm/parameters/backlit"
alias bn="echo 0 | sudo tee /sys/module/sharp_drm/parameters/backlit"
EOF
