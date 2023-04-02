#!/bin/bash
USERNAME=$SUDO_USER
if [ -z "${USERNAME}" ];
then
    echo "Can't get User Name"
    exit 1
fi

function init(){
    # [Security] Skip password when sudo. The format is "${USERNAME} ALL=NOPASSWD: ALL"
    if ! grep -q ${USERNAME} /etc/sudoers;
    then
        echo ${USERNAME} ALL=NOPASSWD: ALL >> /etc/sudoers
    fi

    # APT update/upgrade
    apt-get -y update
    apt-get -y upgrade
    
    # https://github.com/whiteleaf7/narou
    # https://github.com/kyukyunyorituryo/AozoraEpub3

    # Install Ruby Java
    mkdir narou
    cd narou
    apt-get -y --force-yes install ruby-full default-jdk
    gem install narou
    wget https://github.com/kyukyunyorituryo/AozoraEpub3/releases/download/v1.1.1b14Q/AozoraEpub3-1.1.1b14Q.zip
    unzip AozoraEpub3-1.1.1b14Q.zip

    narou init
}

if [ $# = 0 ];
then
    init
    exit 0
fi

cat << EOF
[Usage]
narou_ubuntu20.sh
EOF
exit 0
