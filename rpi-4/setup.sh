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

# [Manual] Add user to sudoers
if ! grep -q ${USERNAME} /etc/sudoers; then
    cat <<EOF
    [Add to sudoers manually]
    1. Run "sudo visudo"
    2. Add "${USERNAME} ALL=(ALL) NOPASSWD: ALL"
    3. Nano editor shortcut is ctrl+O -> Y -> Y -> ctrl+X
EOF
fi

# apt-get update/upgrade
apt-get -y update
apt-get -y upgrade
apt-get -y purge needrestart
apt-get -y install raspi-config

# set vim as default
update-alternatives --set editor /usr/bin/vim.basic

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
tmpfs   /var/log    tmpfs   defaults,size=32m,noatime,mode=0750     0   0
EOF
fi

# Make /etc/init.d/prep-varlog to setup /var/log
CONFIG=/etc/init.d/prep-varlog
cat <<EOF >${CONFIG}
#!/bin/bash
#
### BEGIN INIT INFO
# Provides:          prep-varlog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Required-Start:
# Required-Stop:
# Short-Description: Create /var/log/... files on tmpfs at startup
# Description:       Create /var/log/... files needed by system daemon
### END INIT INFO

case "\${1:-''}" in
  'start')
    # Prepare folders
    mkdir -p /var/log/ConsoleKit
    mkdir -p /var/log/apache2
    mkdir -p /var/log/apt
    mkdir -p /var/log/fsck
    mkdir -p /var/log/mysql
    mkdir -p /var/log/nginx

    chown www-data /var/log/nginx
    chmod 750 /var/log/nginx

    chown www-data /var/log/apache2
    chmod 750 /var/log/apache2

    chown mysql /var/log/mysql
    chmod 750 /var/log/mysql

    # Prepare /var/log file for ramdisk init on every boot
    touch /var/log/lastlog
    touch /var/log/wtmp
    touch /var/log/btmp
    touch /var/log/apache2/access.log
    touch /var/log/apache2/error.log
    touch /var/log/apache2/ssl_access.log
 
    chown www-data /var/log/apache2/access.log
    chown www-data /var/log/apache2/error.log
    chown www-data /var/log/apache2/ssl_access.log

    chmod 640 /var/log/apache2/access.log
    chmod 640 /var/log/apache2/error.log
    chmod 640 /var/log/apache2/ssl_access.log

    chown root /var/log/lastlog
    chown root /var/log/wtmp
    chown root /var/log/btmp
   ;;
  'stop')
   ;;
  'restart')
   ;;
  'reload'|'force-reload')
   ;;
  'status')
   ;;
  *)
   echo "Usage: $SELF start"
   exit 1
   ;;
esac
EOF
chmod 755 ${CONFIG}
update-rc.d prep-varlog defaults 01 10
# update-rc.d no longer does anything but call insserv nowadays to do all
# update-rc.d apache2 defaults 02 10
# update-rc.d mysql defaults 02 10
# update-rc.d nginx defaults 02 10

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
