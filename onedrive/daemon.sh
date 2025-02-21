#!/bin/bash

# https://github.com/abraunegg/onedrive/blob/master/docs/usage.md

USERNAME=$SUDO_USER
if [ -z "${USERNAME}" ]; then
    echo "Can't get User Name"
    exit 1
fi

apt install onedrive

# Clean up
if [ -e /etc/systemd/user/default.target.wants/onedrive.service ]; then
    rm /etc/systemd/user/default.target.wants/onedrive.service
fi

systemctl disable --now onedrive@${USERNAME}.service
pid_onedrive=$(pidof onedrive)
if [ -n "${pid_onedrive}" ]; then
    kill -9 ${pid_onedrive}
fi

systemctl enable --now onedrive@${USERNAME}.service

systemctl status onedrive@${USERNAME}.service
