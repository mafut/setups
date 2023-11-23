#!/bin/bash

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

# xset https://www.waveshare.com/wiki/4.3inch_DSI_LCD
apt-get install -y --allow x11-xserver-utils

# Screensaver: cmatrix
apt-get install -y --allow cmatrix

# Screensaver: termsaver
apt-get install python3-pip build-essential
sudo -u ${USERNAME} pip install termsaver

# Configure to run screensaver before login as info hub
CONFIG=/usr/local/bin/loginScreensaver.sh
cat <<EOF >${CONFIG}
#!/bin/bash
# /usr/bin/cmatrix -abs
termsaver clock
exec /bin/login
EOF
chmod 744 /usr/local/bin/loginScreensaver.sh

CONFIG=/etc/systemd/system/getty@tty1.service.d/override.conf
cat <<EOF >${CONFIG}
[Service]
ExecStart=
ExecStart=-/usr/local/bin/loginScreensaver.sh
StandardInput=tty
StandardOutput=tty
EOF
