#!/bin/bash

WIFIPOINT=$1
WIFIPASS=$2

if [ -z "${WIFIPOINT}" ] || [ -z "${WIFIPASS}" ];
then
    echo "Usage: this_script.sh [wifi point] [wifi pass]"
    exit 1
fi

# Add ubuntu to sudoers
# If doesn't work, 
# Run "sudo visudo" and Add "ubuntu ALL=NOPASSWD:ALL"
# Nano editor shortcut is ctrl+O -> Y -> Y -> ctrl+X
if ! grep -q ${USERNAME} /etc/sudoers;
then
    echo ${USERNAME} ALL=NOPASSWD: ALL >> /etc/sudoers
fi

# apt-get update/upgrade
apt-get -y --force-yes update
apt-get -y --force-yes upgrade

# Remove swap
apt-get autoremove -y dphys-swapfile

# RAM Disk
if ! grep -q tmpfs /etc/fstab;
then
    CONFIG=/etc/fstab
    cat << EOF >> ${CONFIG}
tmpfs   /tmp        tmpfs   defaults,size=256m,noatime,mode=1777    0   0
tmpfs   /var/tmp    tmpfs   defaults,size=16m,noatime,mode=1777     0   0
tmpfs   /var/log    tmpfs   defaults,size=32m,noatime,mode=0755     0   0
EOF
fi

# Fix ssh server
if [ ! -f /etc/ssh/ssh_host_key ] && [ ! -f /etc/ssh/ssh_host_dsa_key ]; then
    echo Add /etc/ssh/ssh_host_key and /etc/ssh/ssh_host_dsa_key
    ssh-keygen -A
fi

# Connect Wifi
CONFIG=/etc/netplan/50-cloud-init.yaml
cat << EOF > ${CONFIG}
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
