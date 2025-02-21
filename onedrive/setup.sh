#!/bin/bash

# https://github.com/abraunegg/onedrive/blob/master/docs/usage.md

USERNAME=$SUDO_USER
if [ -z "${USERNAME}" ]; then
    echo "Can't get User Name"
    exit 1
fi

apt install --no-install-recommends --no-install-suggests onedrive

# Clean up
if [ -e /etc/systemd/user/default.target.wants/onedrive.service ]; then
    rm /etc/systemd/user/default.target.wants/onedrive.service
fi

systemctl disable --now onedrive@${USERNAME}.service
pid_onedrive=$(pidof onedrive)
if [ -n "${pid_onedrive}" ]; then
    kill -9 ${pid_onedrive}
fi

# Config
CONFIG=/home/${USERNAME}/.config/onedrive/config
cat <<EOF >${CONFIG}
sync_dir = "/home/${USERNAME}/OneDrive"
check_nosync = "true"
no_remote_delete = "true"
skip_dotfiles = "true"
skip_symlinks = "true"
skip_dir = "Comics|Documents|Game|Music|Pictures|Setup|Videos"

monitor_interval = "600"
monitor_fullscan_frequency = "12"
monitor_log_frequency = "12"

disable_notifications = "true"
EOF

# Sync list
CONFIG=/home/${USERNAME}/.config/onedrive/sync_list
cat <<EOF >${CONFIG}
!/*/*
/Notes/
/Backup/
EOF

# Initialize
sudo -u ${USERNAME} onedrive --synchronize --download-only

read -p "Hit enter to run with --resync: "

sudo -u ${USERNAME} onedrive --synchronize --download-only --resync
