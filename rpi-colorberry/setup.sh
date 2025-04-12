#!/bin/bash
DIR_COMMON=$(
    cd $(dirname $0)
    cd ../rpi-common/
    pwd
)

source ${DIR_COMMON}/setup.sh

apt-get -y install raspberrypi-kernel-headers i2c-tools unzip

# Display
# https://github.com/hyphenlee/jdi-drm-rpi
if [ ! -e /boot/overlays/sharp-drm.dtbo ]; then
    unzip -o ${DIR_SELF}/jdi-drm-rpi-debian11-32.zip -d /var/tmp/
    cd /var/tmp/jdi-drm-rpi
    make install
fi

# Keyboard
# https://github.com/sqfmi/bbqX0kbd_driver
# https://github.com/ardangelo/beepberry-keyboard-driver
if [ ! -e /boot/overlays/beepy-kbd.dtbo ]; then
    unzip -o ${DIR_SELF}/beepy-kbd-ardangelo.zip -d /var/tmp/
    cd /var/tmp/beepberry-keyboard-driver-main
    make install
fi
if [ ! -e /boot/overlays/beepy-kbd.dtbo ]; then
    unzip ${DIR_SELF}/beepy-kbd-sqfmi.zip -d /var/tmp/ -o
    cd /var/tmp/bbqX0kbd_driver-main
    make install
fi

# Backlight
cp -f ${DIR_SELF}/side-button.py /usr/local/sbin/side-button.py
chmod +x /usr/local/sbin/side-button.py

cat <<EOF >/var/tmp/crontab.txt
@reboot   sleep 5;/usr/local/sbin/side-button.py
@reboot   loadkeys '/usr/share/kbd/keymaps/beepy-kbd.map'
EOF
crontab /var/tmp/crontab.txt

# bash_aliases (append)
cat <<EOF >>${FILE_BASHALIASES}
alias d0="echo 0 | sudo tee /sys/module/sharp_drm/parameters/dither"
alias d1="echo 1 | sudo tee /sys/module/sharp_drm/parameters/dither"
alias d2="echo 2 | sudo tee /sys/module/sharp_drm/parameters/dither"
alias d3="echo 3 | sudo tee /sys/module/sharp_drm/parameters/dither"
alias d4="echo 4 | sudo tee /sys/module/sharp_drm/parameters/dither"
alias by="echo 1 | sudo tee /sys/module/sharp_drm/parameters/backlit"
alias bn="echo 0 | sudo tee /sys/module/sharp_drm/parameters/backlit"
alias km="sudo cp -f ${DIR_SELF}/keyboard.map /usr/share/kbd/keymaps/beepy-kbd.map && sudo loadkeys /usr/share/kbd/keymaps/beepy-kbd.map"
alias bp="cat /sys/firmware/beepy/battery_percent"

unalias ls
EOF

# .tmux.conf (override)
cat <<EOF >${FILE_TMUXCONFIG}
set-window-option -g mode-keys vi
set-option -g base-index 1
set-option -g mouse on
set-option -g default-terminal "screen"
set-option -g status-bg "blue"
set-option -g status-fg "white"
set -g mouse on
set -g terminal-overrides 'xterm*:smcup@:rmcup@'
set -g status-position top
set -g status-left ""
set -g status-right "#(cat /sys/firmware/beepy/battery_percent)%|#{primary_ip}|%H:%M"
set -g status-interval 10
set -g window-status-separator ' | '
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-sensible'
set -g @plugin 'gmoe/tmux-wifi'
set -g @plugin 'dreknix/tmux-primary-ip'
run '~/.tmux/plugins/tpm/tpm'
EOF
chown ${USERNAME}:${USERNAME} ${FILE_TMUXCONFIG}

systemctl enable keyboard-setup
