#!/bin/bash


WIFIPOINT=$1
WIFIPASS=$2

if [ -z "${WIFIPOINT}" ] || [ -z "${WIFIPASS}" ]; then
    echo "Usage: this_script.sh [wifi point] [wifi pass]"
    exit 1
fi

# Add ubuntu to sudoers
echo Add to sudoers
echo "1. Run \"sudo visudo\""
echo "2. Add \"ubuntu ALL=NOPASSWD:ALL\""
echo "3. Nano editor shortcut is ctrl+O -> Y -> Y -> ctrl+X"

# apt-get update/upgrade
echo apt-get update/upgrade
apt-get -y --force-yes update
apt-get -y --force-yes upgrade

# set time zone
timedatectl set-timezone America/Los_Angeles

# Remove Swap
echo Remove Swap
apt-get autoremove -y dphys-swapfile
swapoff --all

# RAM Disk
echo Configure RAM Disk
if ! grep -q tmpfs /etc/fstab; then
    CONFIG=/etc/fstab
    cat <<EOF >>${CONFIG}
tmpfs   /tmp        tmpfs   defaults,size=256m,noatime,mode=1777    0   0
tmpfs   /var/tmp    tmpfs   defaults,size=16m,noatime,mode=1777     0   0
tmpfs   /var/log    tmpfs   defaults,size=32m,noatime,mode=0755     0   0
EOF
fi

# https://www.waveshare.com/wiki/4.3inch_DSI_LCD
echo Install xset
apt-get install -y --force-yes x11-xserver-utils

# screen saver before login
echo Configure cmatrix
apt-get install -y --force-yes cmatrix

echo Configure termsaver
apt-get install python3-pip build-essential
pip install termsaver

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

# Fix ssh server
echo Fix ssh host
if [ ! -f /etc/ssh/ssh_host_key ] && [ ! -f /etc/ssh/ssh_host_dsa_key ]; then
    echo Add /etc/ssh/ssh_host_key and /etc/ssh/ssh_host_dsa_key
    ssh-keygen -A
fi

# Add Wifi Access Point
echo Configure WiFi Access Point
CONFIG=/etc/netplan/50-cloud-init.yaml

if ! grep -q ${WIFIPOINT} ${CONFIG}; then
    cat <<EOF >${CONFIG}
network:
    ethernets:
        eth0:
            dhcp4: true
            optional: true
    version: 2
    wifis:
        wlan0:
            dhcp4: true
            optional: true
            access-points:
                ${WIFIPOINT}:
                    password: "${WIFIPASS}"
EOF
    netplan apply
fi
