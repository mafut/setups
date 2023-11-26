#!/bin/bash

# This is for
# https://www.waveshare.com/4.3inch-DSI-LCD.htm
# https://www.waveshare.com/wiki/4.3inch_DSI_LCD

SCRIPT_PATH=$(
    cd $(dirname $0)
    pwd
)

# Check sudo or not
USERNAME=$SUDO_USER
if [ -z "${USERNAME}" ]; then
    echo "Can't get User Name"
    exit 1
fi

./setup.sh

# xset
apt-get install -y x11-xserver-utils

# Screensaver: cmatrix
apt-get install -y cmatrix

# Screensaver: termsaver
apt-get install  build-essential python3-pip python3-venv python-is-python3
sudo -u ${USERNAME} python -m venv env-${USERNAME}
sudo -u ${USERNAME} pip install termsaver --user

# Configure to run screensaver before login as info hub
CONFIG=/usr/local/bin/loginScreensaver.sh
cat <<EOF >${CONFIG}
#!/bin/bash
# /usr/bin/cmatrix -abs
termsaver clock
exec /bin/login
EOF
chmod 755 /usr/local/bin/loginScreensaver.sh

if [ ! -d "/etc/systemd/system/getty@tty1.service.d/" ]; then
    mkdir /etc/systemd/system/getty@tty1.service.d/
fi
CONFIG=/etc/systemd/system/getty@tty1.service.d/override.conf
cat <<EOF >${CONFIG}
[Service]
ExecStart=
ExecStart=-/usr/local/bin/loginScreensaver.sh
StandardInput=tty
StandardOutput=tty
EOF
