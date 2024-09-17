#!/bin/bash

USERNAME=$SUDO_USER
if [ -z "${USERNAME}" ]; then
    echo "Can't get User Name"
    exit 1
fi

apt install onedrive
rm /etc/systemd/user/default.target.wants/onedrive.service

CONFIG=/home/${USERNAME}/.config/onedrive/config
cat <<EOF >${CONFIG}
sync_dir = "~/OneDrive/Notes"
check_nosync = "true"
no_remote_delete = "true"
skip_dotfiles = "true"

monitor_interval = "600"
monitor_fullscan_frequency = "12"
monitor_log_frequency = "12"

disable_notifications = "true"
EOF

CONFIG=/home/${USERNAME}/.config/onedrive/sync_list
cat <<EOF >${CONFIG}
/Notes
EOF

onedrive --synchronize --download-only --check-for-nosync --no-remote-delete --single-directory 'Notes'
# onedrive --synchronize
systemctl enable onedrive@${USERNAME}.service
systemctl start onedrive@${USERNAME}.service
