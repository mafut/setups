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
FILE_FSTAB=/etc/fstab
FILE_RAMDISKSH=/usr/local/sbin/varlogtmp.sh
FILE_RAMDISKSVC=/etc/systemd/system/varlogtmp.service
FILE_RSYSLOG=/etc/rsyslog.conf
FILE_SSHD=/etc/ssh/sshd_config
FILE_SSHKEY=/home/${USERNAME}/.ssh/authorized_keys
FILE_SSHCONF=/home/${USERNAME}/.ssh/config
FILE_BASHPROFILE=/home/${USERNAME}/.bash_profile
FILE_BASHALIASES=/home/${USERNAME}/.bash_aliases
FILE_TMUXCONFIG=/home/${USERNAME}/.tmux.conf
FILE_LIBYKCS11=/usr/lib/aarch64-linux-gnu/libykcs11.so
if [ ! -e ${FILE_LIBYKCS11} ]; then
    FILE_LIBYKCS11=/usr/lib/arm-linux-gnueabihf/libykcs11.so
fi

# SSH_AUTHKEYS_TMP
DIR_PUB=$(
    cd $(dirname $0)
    cd ../ssh-pubkey/
    pwd
)
DIR_PUBS=(
    ${DIR_PUB}/yubikey/
    ${DIR_PUB}/client/
)

SSH_AUTHKEYS_TMP=/home/${USERNAME}/.ssh/authorized_keys.tmp

if [ ! -e $(dirname ${SSH_AUTHKEYS_TMP}) ]; then
    sudo -u ${USERNAME} mkdir $(dirname ${SSH_AUTHKEYS_TMP})
fi
sudo -u ${USERNAME} echo -n >${SSH_AUTHKEYS_TMP}

for pubs in "${DIR_PUBS[@]}"; do
    if [ -e $pubs ]; then
        # {} represents the file being operated on during this iteration
        # \; closes the code statement and returns for next iteration
        find "$pubs" -name "*.pub" -type f -exec awk '1' $1 >>${SSH_AUTHKEYS_TMP} {} \;
    fi
done

if [ ! -s ${SSH_AUTHKEYS_TMP} ]; then
    echo "Can't get public certs"
    exit 1
fi

# apt-get update/upgrade
apt-get -y update
apt-get -y upgrade
apt-get -y purge bluez avahi-daemon triggerhappy modemmanager
apt-get -y install rsyslog moreutils vim ufw raspi-config network-manager tty-clock gpm ykcs11 tmux
apt-get -y autoremove 

# apt update/upgrade
apt -y update
apt -y upgrade
apt -y autoremove

# raspi-config
raspi-config nonint do_i2c 0
raspi-config nonint do_spi 0
raspi-config nonint do_boot_behaviour B2

# set time zone
timedatectl set-timezone America/Los_Angeles

# Remove Swap
swapoff -a
systemctl disable dphys-swapfile
free -h

# Setup Ram Disk (Check the result by 'df -h')
if ! grep -q tmpfs ${FILE_FSTAB}; then
    cat <<EOF >>${FILE_FSTAB}
tmpfs   /tmp        tmpfs   defaults,size=16m,noatime,mode=1777     0   0
tmpfs   /var/tmp    tmpfs   defaults,size=64m,noatime,mode=1777     0   0
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
ufw --force enable

# sshd
sed "s|#PubkeyAuthentication yes|PubkeyAuthentication yes|g" ${FILE_SSHD} | sponge ${FILE_SSHD}
sed "s|#AuthorizedKeysFile|AuthorizedKeysFile|g" ${FILE_SSHD} | sponge ${FILE_SSHD}
sed "s|#PasswordAuthentication yes|PasswordAuthentication no|g" ${FILE_SSHD} | sponge ${FILE_SSHD}

# ssh_host_key / ssh_host_dsa_key
if [ ! -e /etc/ssh/ssh_host_rsa_key ] && [ ! -e /etc/ssh/ssh_host_ed25519_key ]; then
    echo Add /etc/ssh/ssh_host_rsa_key and /etc/ssh/ssh_host_ed25519_key
    ssh-keygen -A
fi

# ssh conf
mv -f ${SSH_AUTHKEYS_TMP} ${FILE_SSHKEY}
cat ${FILE_SSHKEY}

if [ ! -e ${FILE_SSHCONF} ]; then
    cat <<EOF >${FILE_SSHCONF}
PKCS11Provider ${FILE_LIBYKCS11}
EOF
fi

# tmux
if [ ! -e "/home/${USERNAME}/.tmux/plugins/tpm" ]; then
    git clone https://github.com/tmux-plugins/tpm /home/${USERNAME}/.tmux/plugins/tpm
fi
chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.tmux/

# .tmux.conf
cat <<EOF >${FILE_TMUXCONFIG}
set-window-option -g mode-keys vi
set-option -g base-index 1
set-option -g mouse on
set-option -g default-terminal "screen-256color"
set-option -g status-bg "colour235"
set-option -g status-fg "colour255"
set -g mouse on
set -g terminal-overrides 'xterm*:smcup@:rmcup@'
set -g status-position top
set -g status-left ""
set -g status-right "#H|#{primary_ip}|%H:%M"
set -g status-interval 10
set -g window-status-separator ' | '
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-sensible'
set -g @plugin 'gmoe/tmux-wifi'
set -g @plugin 'dreknix/tmux-primary-ip'
run '~/.tmux/plugins/tpm/tpm'
EOF
chown ${USERNAME}:${USERNAME} ${FILE_TMUXCONFIG}

# .bash_profile
cat <<EOF >${FILE_BASHPROFILE}
export PATH=”\$PATH:/home/${USERNAME}/.local/bin”

setterm --foreground white --bold on

tmux_count=\$(ps -ax | grep '[t]mux' | wc -l)
if [[ \$SHLVL = 1 && \$tmux_count = 0 ]]; then
	tmux -u new-session
elif [[ \$SHLVL = 1 && \$tmux_count = 1 ]]; then
	tmux -u attach
fi

test -r ~/.bashrc && . ~/.bashrc
EOF
chown ${USERNAME}:${USERNAME} ${FILE_BASHPROFILE}

# .bash_aliases
cat <<EOF >${FILE_BASHALIASES}
alias sshyk='ssh -I ${FILE_LIBYKCS11}'
alias scpyk='scp -F ${FILE_SSHCONF}'

alias cls='setterm --clear all --foreground white --bold on --store'
alias home='cd /home/${USERNAME}/ && source ${FILE_BASHPROFILE}'
alias latest='cd ${DIR_SELF} && git pull && sudo ${DIR_SELF}/setup.sh && cd /home/${USERNAME}/ && source ${FILE_BASHPROFILE}'
alias setup='sudo ./setup.sh'

alias font='sudo dpkg-reconfigure console-setup'
alias config='sudo raspi-config'
alias clock='tty-clock -scbrBS'
alias wifi='nmcli device wifi connect'

alias up='cd ..'
alias l='ls -CF'
alias la='ls -A'
alias ll='ls -alF'
alias ls='ls --color=auto'
alias ps='ps -ax'

alias off='sudo shutdown now'
EOF
chown ${USERNAME}:${USERNAME} ${FILE_BASHALIASES}

# Restart
systemctl disable polkit
systemctl disable keyboard-setup
systemctl daemon-reload
systemctl restart rsyslog
systemctl restart sshd
