#!/bin/bash

# https://github.com/abraunegg/onedrive/blob/master/docs/usage.md

USERNAME=$SUDO_USER
if [ -z "${USERNAME}" ]; then
    echo "Can't get User Name"
    exit 1
fi

apt install onedrive
if [ -e /etc/systemd/user/default.target.wants/onedrive.service ]; then
    rm /etc/systemd/user/default.target.wants/onedrive.service
fi
systemctl disable onedrive@${USERNAME}.service

CONFIG=/home/${USERNAME}/.config/onedrive/config
cat <<EOF >${CONFIG}
sync_dir = "~/OneDrive"
check_nosync = "true"
no_remote_delete = "true"
skip_dotfiles = "true"
skip_symlinks = "true"
skip_dir = "Documents|Game|Music|Pictures|Videos"

monitor_interval = "600"
monitor_fullscan_frequency = "12"
monitor_log_frequency = "12"

disable_notifications = "true"
EOF

CONFIG=/home/${USERNAME}/.config/onedrive/sync_list
cat <<EOF >${CONFIG}
!/*/*
/Notes/
EOF

#sudo -u ${USERNAME} onedrive --synchronize --check-for-nosync --no-remote-delete --single-directory 'Notes'
sudo -u ${USERNAME} onedrive --synchronize --check-for-nosync --no-remote-delete

read -p "Hit enter if continue: "

systemctl enable onedrive@${USERNAME}.service
systemctl start onedrive@${USERNAME}.service
