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
    # https://qiita.com/hirohiro77/items/13ef7354042967e352c4

    # Install Ruby Java
    mkdir narou
    cd narou
    apt-get -y --allow install ruby-full default-jdk epub-utils calibre
    gem install narou
    wget https://github.com/kyukyunyorituryo/AozoraEpub3/releases/download/v1.1.1b14Q/AozoraEpub3-1.1.1b14Q.zip
    unzip AozoraEpub3-1.1.1b14Q.zip
    cd AozoraEpub3-1.1.1b14Q
    cat << EOF > kindlegen
#!/bin/sh
INPUTFILE="$3"
OUTPUTFILE=`echo "$3"|sed 's/\.epub/\.mobi/g'`
/usr/bin/ebook-convert "${INPUTFILE}" "${OUTPUTFILE}"
EOF
    chmod 777 kindlegen

    narou init
    narou s convert.no-strip=true
    narou s convert.no-open=true
    narou s convert.no-mobi=true
    narou s convert.copy_to="/home/${USERNAME}/epub"
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
