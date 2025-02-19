#!/bin/bash

# Check sudo or not
USERNAME=$SUDO_USER
if [ -z "${USERNAME}" ]; then
    echo "Can't get User Name"
    exit 1
fi

# Variables
DIR_SELF=$(
    cd $(dirname $0)
    pwd
)
DIR_PUB=$(
    cd $(dirname $0)
    cd ..
    cd ssh-pubkey
    pwd
)
FILE_FSTAB=/etc/fstab
FILE_RAMDISKSH=/usr/local/sbin/varlogtmp.sh
FILE_RAMDISKSVC=/etc/systemd/system/varlogtmp.service
FILE_RSYSLOG=/etc/rsyslog.conf
FILE_SSHD=/etc/ssh/sshd_config
FILE_SSHKEY=/home/${USERNAME}/.ssh/authorized_keys
FILE_SSHCONF=/home/${USERNAME}/.ssh/config
FILE_BASHPROFILE=/home/${USERNAME}/.bash_profile
FILE_LIBYKCS11=/usr/lib/arm-linux-gnueabihf/libykcs11.so

# apt-get update/upgrade
apt-get -y update
apt-get -y upgrade
apt-get -y purge bluez
apt-get -y install rsyslog moreutils vim ufw raspi-config tty-clock chkconfig gpm ykcs11
apt-get -y autoremove 

# set time zone
timedatectl set-timezone America/Los_Angeles

# Remove Swap
swapoff -a
chkconfig dphys-swapfile --list
chkconfig dphys-swapfile off
systemctl disable dphys-swapfile
free -h

# Setup Ram Disk (Check the result by 'df -h')
if ! grep -q tmpfs ${FILE_FSTAB}; then
    cat <<EOF >>${FILE_FSTAB}
tmpfs   /tmp        tmpfs   defaults,size=16m,noatime,mode=1777     0   0
tmpfs   /var/tmp    tmpfs   defaults,size=32m,noatime,mode=1777     0   0
tmpfs   /var/log    tmpfs   defaults,size=16m,noatime,mode=0750     0   0
EOF
fi

# Setup /var/log, /var/tmp, /tmp
# Add in init.d: old (including calling varlogtmp.sh in /etc/rc.local)
# Add in systemd: new
cat <<EOF >${FILE_RAMDISKSH}
#!/bin/bash

# Prepare /var/log file for ramdisk init on every boot
# Add if when new service

# Folders
mkdir -p /var/log/apt
mkdir -p /var/log/fsck
mkdir -p /var/log/journal
mkdir -p /var/log/runit

chown root:systemd-journal /var/log/journal

# Files
touch /var/log/lastlog
touch /var/log/btmp
touch /var/log/wtmp
touch /var/log/dpkg.log
touch /var/log/syslog
touch /var/log/auth.log
touch /var/log/kern.log
touch /var/log/ufw.log

chown root /var/log/lastlog
chown root:utmp /var/log/btmp
chown root:utmp /var/log/wtmp
chown root:adm /var/log/syslog
chown root:adm /var/log/auth.log
chown root:adm /var/log/kern.log
chown root:adm /var/log/ufw.log
EOF
chmod 755 ${FILE_RAMDISKSH}

cat <<EOF >${FILE_RAMDISKSVC}
[Unit]
After=local-fs.target
Before=rsyslog.service

[Service]
ExecStart=${FILE_RAMDISKSH}
Type=oneshot
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
chmod 644 ${FILE_RAMDISKSVC}
systemctl enable $(basename ${FILE_RAMDISKSVC})

# rsyslog
sed "s|^cron\.*|#cron.*|g" ${FILE_RSYSLOG} | sponge ${FILE_RSYSLOG}
sed "s|^daemon\.*|#daemon.*|g" ${FILE_RSYSLOG} | sponge ${FILE_RSYSLOG}
sed "s|^kern\.*|#kern.*|g" ${FILE_RSYSLOG} | sponge ${FILE_RSYSLOG}
sed "s|^mail\.*|#mail.*|g" ${FILE_RSYSLOG} | sponge ${FILE_RSYSLOG}
sed "s|^user\.*|#user.*|g" ${FILE_RSYSLOG} | sponge ${FILE_RSYSLOG}

# ufw
ufw disable
ufw --force reset
ufw default deny
ufw allow 22
ufw limit 22
ufw enable

# sshd
sed "s|#PubkeyAuthentication yes|PubkeyAuthentication yes|g" ${FILE_SSHD} | sponge ${FILE_SSHD}
sed "s|#AuthorizedKeysFile|AuthorizedKeysFile|g" ${FILE_SSHD} | sponge ${FILE_SSHD}
sed "s|#PasswordAuthentication yes|PasswordAuthentication no|g" ${FILE_SSHD} | sponge ${FILE_SSHD}

# ssh
if [ ! -e $(dirname ${FILE_SSHKEY}) ]; then
    sudo -u ${USERNAME} mkdir $(dirname ${FILE_SSHKEY})
fi
if [ -e ${FILE_SSHKEY} ]; then
    mv -f ${FILE_SSHKEY} ${FILE_SSHKEY}.bak
fi
find "${DIR_PUB}/yubikey" -name "*.pub" -type f -exec awk '1' $1>>${FILE_SSHKEY} {} \;
find "${DIR_PUB}/client" -name "*.pub" -type f -exec awk '1' $1>>${FILE_SSHKEY} {} \;
# {} represents the file being operated on during this iteration
# \; closes the code statement and returns for next iteration
cat ${FILE_SSHKEY}

if [ ! -e ${FILE_SSHCONF} ]; then
    cat <<EOF >${FILE_SSHCONF}
PKCS11Provider ${FILE_LIBYKCS11}
EOF
fi

# mdless and mdl
apt-get -y install ruby-dev ruby
gem install mdless
gem install mdl

# .bash_profile
cat <<EOF >${FILE_BASHPROFILE}
export PATH=”\$PATH:/home/${USERNAME}/.local/bin”

alias sshyk='ssh -I ${FILE_LIBYKCS11}'
alias scp='scp -F ${FILE_SSHCONF}'

alias latest='cd ${DIR_SELF} && git pull && sudo ${DIR_SELF}/setup.sh && source ${FILE_BASHPROFILE} && cd /home/${USERNAME}/'
alias home='source ${FILE_BASHPROFILE} && cd /home/${USERNAME}/ && clear'

alias font='sudo dpkg-reconfigure console-setup'
alias config='sudo raspi-config'
alias cls='clear'
alias off='sudo shutdown now'
alias on='tty-clock -scbrBS'
alias rb='sudo reboot now'
EOF
chown ${USERNAME}:${USERNAME} ${FILE_BASHPROFILE}

# Restart
systemctl daemon-reload
systemctl restart rsyslog
systemctl restart sshd
