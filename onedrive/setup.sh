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

# Config
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

# Sync list
CONFIG=/home/${USERNAME}/.config/onedrive/sync_list
cat <<EOF >${CONFIG}
!/*/*
/Notes/
/Backup/
EOF

# Initialize
sudo -u ${USERNAME} onedrive --synchronize --download-only --cleanup-local-files

# Tips
cat <<EOF

Manually run one of the following to initialize
onedrive --synchronize --download-only --cleanup-local-files
onedrive --synchronize --download-only --cleanup-local-files --resync

onedrive --synchronize --check-for-nosync --no-remote-delete
onedrive --synchronize --check-for-nosync --no-remote-delete --resync

onedrive --synchronize --check-for-nosync --no-remote-delete --single-directory 'Notes'
onedrive --synchronize --check-for-nosync --no-remote-delete --single-directory 'Backup'

If the following error happens, check known solution
- disk I/O error -> stop service and kill onedrive process
- The database is currently locked by another process -> same as disk io error

process can be checked by "pidof onedrive"

EOF