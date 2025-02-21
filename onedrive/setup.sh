#!/bin/bash

# https://github.com/abraunegg/onedrive/blob/master/docs/usage.md

USERNAME=$SUDO_USER
if [ -z "${USERNAME}" ]; then
    echo "Can't get User Name"
    exit 1
fi

apt install onedrive

# Clean up for sure
if [ -e /etc/systemd/user/default.target.wants/onedrive.service ]; then
    rm /etc/systemd/user/default.target.wants/onedrive.service
fi

CONFIG=/home/${USERNAME}/.config/onedrive/config
cat <<EOF >${CONFIG}
sync_dir = "/home/${USERNAME}/OneDrive"
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
/Backup/
EOF

cat <<EOF

Manually run one of the following to initialize
onedrive --synchronize --check-for-nosync --no-remote-delete
onedrive --synchronize --check-for-nosync --no-remote-delete --resync
onedrive --synchronize --check-for-nosync --no-remote-delete --single-directory 'Notes'
onedrive --synchronize --check-for-nosync --no-remote-delete --single-directory 'Backup'

If the following error happens, check known solution
- disk I/O error -> stop service and kill onedrive process
- The database is currently locked by another process -> same as disk io error

process can be checked by "pidof onedrive"

EOF

read -p "Hit enter to start as service: "

pid_onedrive=$(pidof onedrive)
systemctl disable --now onedrive@${USERNAME}.service
kill -9 ${pid_onedrive}

systemctl enable --now onedrive@${USERNAME}.service

systemctl status onedrive@${USERNAME}.service
