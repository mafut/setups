#!/bin/bash

SCRIPT_PATH=$(
    cd $(dirname $0)
    pwd
)

WIFIPOINT=$1
WIFIPASS=$2

if [ -z "${WIFIPOINT}" ] || [ -z "${WIFIPASS}" ]; then
    echo "Usage: this_script.sh [wifi point] [wifi pass]"
    exit 1
fi

# Check sudo or not
USERNAME=$SUDO_USER
if [ -z "${USERNAME}" ]; then
    echo "Can't get User Name"
    exit 1
fi

# [Manual] Add user to sudoers
if ! grep -q ${USERNAME} /etc/sudoers; then
    echo Add to sudoers manually
    echo "1. Run \"sudo visudo\""
    echo "2. Add \"${USERNAME} ALL=(ALL) NOPASSWD:ALL\""
    echo "3. Nano editor shortcut is ctrl+O -> Y -> Y -> ctrl+X"
fi

# apt-get update/upgrade
apt-get -y --force-yes update
apt-get -y --force-yes upgrade
apt-get -y --force-yes purge needrestart
apt-get -u --force-yes raspi-config

# set time zone
timedatectl set-timezone America/Los_Angeles

# Remove Swap
apt-get autoremove -y dphys-swapfile
swapoff --all

# RAM Disk
if ! grep -q tmpfs /etc/fstab; then
    CONFIG=/etc/fstab
    cat <<EOF >>${CONFIG}
tmpfs   /tmp        tmpfs   defaults,size=256m,noatime,mode=1777    0   0
tmpfs   /var/tmp    tmpfs   defaults,size=256m,noatime,mode=1777    0   0
tmpfs   /var/log    tmpfs   defaults,size=32m,noatime,mode=0777     0   0
EOF
fi

# npm/nodejs
NODE_MAJOR=16
apt-get install -y ca-certificates curl gnupg
if [ ! -f /etc/apt/keyrings/nodesource.gpg ]; then
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
fi
apt-get update
apt-get install npm nodejs -y

# Resource monitor blessed-contrib https://github.com/yaronn/blessed-contrib
# git clone https://github.com/yaronn/blessed-contrib.git
# npm install
# node ./examples/dashboard.js

# Resource monitor gtop https://github.com/aksakalli/gtop
git clone https://github.com/aksakalli/gtop.git /home/${USERNAME}/gtop
cd /home/${USERNAME}/gtop
npm install gtop -g
cd ${SCRIPT_PATH}

# Fix ssh server
if [ ! -f /etc/ssh/ssh_host_key ] && [ ! -f /etc/ssh/ssh_host_dsa_key ]; then
    echo Add /etc/ssh/ssh_host_key and /etc/ssh/ssh_host_dsa_key
    ssh-keygen -A
fi

# Add Wifi Access Point
CONFIG=/etc/netplan/50-cloud-init.yaml
if ! grep -q ${WIFIPOINT} ${CONFIG}; then
    echo Configure WiFi Access Point
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
