#!/bin/bash
DIR_COMMON=$(
    cd $(dirname $0)
    cd ../rpi-common/
    pwd
)

source ${DIR_COMMON}/setup.sh

apt-get -y install raspberrypi-kernel-headers i2c-tools unzip python3-dbus

# Firmware
# https://github.com/ardangelo/beepberry-rp2040/releases/latest/download/i2c_puppet.uf2

# Display
# https://github.com/arkie/sharp-drm-driver
if [ ! -e /boot/overlays/sharp-drm.dtbo ]; then
    unzip -o ${DIR_SELF}/sharp-drm-driver-arkie.zip -d /var/tmp/
    cd /var/tmp/sharp-drm-driver-master
    make
    make install
fi
# https://github.com/hyphenlee/jdi-drm-rpi
# if [ ! -e /boot/overlays/sharp-drm.dtbo ]; then
#     unzip -o ${DIR_SELF}/jdi-drm-rpi-debian11-32.zip -d /var/tmp/
#     cd /var/tmp/jdi-drm-rpi
#     make install
# fi

# Keyboard
# https://github.com/ardangelo/beepberry-keyboard-driver
if [ ! -e /boot/overlays/beepy-kbd.dtbo ]; then
    unzip -o ${DIR_SELF}/beepy-kbd-ardangelo.zip -d /var/tmp/
    cd /var/tmp/beepberry-keyboard-driver-main
    make
    make install
fi
# https://github.com/sqfmi/bbqX0kbd_driver
# if [ ! -e /boot/overlays/beepy-kbd.dtbo ]; then
#     unzip -o ${DIR_SELF}/beepy-kbd-sqfmi.zip -d /var/tmp/
#     cd /var/tmp/bbqX0kbd_driver-main
#     make install
# fi

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
alias btget="wget https://gist.githubusercontent.com/hishizuka/d66189ec81316945c33531f7d4ddc68d/raw/319621b045254002beb774c701eafe0fc21c0f02/bt-pan && chmod 755 /home/${USERNAME}/bt-pan"
alias bt="sudo /home/${USERNAME}/bt-pan client 14:35:B7:BC:94:11"

unalias ls
EOF

# .tmux.conf (override)
cat <<EOF >${FILE_TMUXCONFIG}
set-window-option -g mode-keys vi
set-option -g base-index 1
set-option -g mouse on
set-option -g default-terminal "screen"
set-option -g status-bg "black"
set-option -g status-fg "white"
set -g mouse on
set -g terminal-overrides 'xterm*:smcup@:rmcup@'
set -g status-position top
set -g status-left ""
set -g status-right "#{primary_ip}|#{wifi_strength}|#(cat /sys/firmware/beepy/battery_percent)%|%H:%M"
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
systemctl enable bluetooth
