#!/bin/bash

USERNAME=$SUDO_USER
if [ -z "${USERNAME}" ];
then
    echo "Can't get User Name"
    exit 1
fi
# [Security] Skip password when sudo. The format is "${USERNAME} ALL=NOPASSWD: ALL"
if ! grep -q ${USERNAME} /etc/sudoers;
then
    echo ${USERNAME} ALL=NOPASSWD: ALL >> /etc/sudoers
fi

# Create folders to mount
if [ ! -d /mnt/setup ]; then
    mkdir /mnt/setup
fi
if [ ! -d /mnt/record ]; then
    mkdir /mnt/records
fi
chmod -R 777 /mnt
apt-get install -y nfs-common

# Mount Host(synology) Shared folders
mount -t nfs 192.168.86.10:/volume1/setup /mnt/setup/
mount -t nfs 192.168.86.10:/volume1/records /mnt/records/

#Add the following in /etc/fstab
if ! grep -q setup /etc/fstab;
then
    echo 192.168.86.10:/volume1/setup /mnt/setup nfs defaults 0 0 >> /etc/fstab
fi
if ! grep -q records /etc/fstab;
then
    echo 192.168.86.10:/volume1/records /mnt/records nfs defaults 0 0 >> /etc/fstab
fi

#install
apt-get install -y curl
curl -sL https://deb.nodesource.com/setup_16.x | sudo bash -
apt-get install -y unzip git cmake g++ build-essential pcscd libpcsclite-dev libccid pcsc-tools automake autoconf autoconf-doc libtool libtool-doc nodejs npm sqlite3 ffmpeg
npm install -y pm2 -g

#unzip PX-S1UD_driver_Ver.1.0.1.zip
cp PX-S1UD_driver_Ver.1.0.1/x64/amd64/isdbt_rio.inp /lib/firmware/

#tar xvzf recdvb-1.3.1.tgz
cd recdvb-1.3.1
./autogen.sh
./configure --enable-b25
make 
make install
cd ..

#git clone https://github.com/stz2012/libarib25.git
cd libarib25
cmake .
make
make install
cd ..

# mirakurun
npm install mirakurun -g --unsafe --production
mirakurun config tuners
cat << EOF > /usr/local/etc/mirakurun/tuners.yml
- name: PX-S1UD-1
  types:
    - GR
  command: recdev --b25 --strip <channel> - -
  isDisabled: false
EOF
mirakurun restart
#curl -X PUT "http://localhost:40772/api/config/channels/scan"

#git clone https://github.com/l3tnun/EPGStation.git
cd EPGStation
npm run all-install
npm run build

cp config/config.yml.template config/config.yml
cp config/operatorLogConfig.sample.yml config/operatorLogConfig.yml
cp config/epgUpdaterLogConfig.sample.yml config/epgUpdaterLogConfig.yml
cp config/serviceLogConfig.sample.yml config/serviceLogConfig.yml
cp config/enc.js.template config/enc.js

pm2 startup
pm2 delete epgstation -u ${USERNAME}
pm2 start dist/index.js --name "epgstation" -u ${USERNAME}
pm2 save -u ${USERNAME}
pm2 list -u ${USERNAME}
pm2 restart epgstation -u ${USERNAME}
cd ..
