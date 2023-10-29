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
if [ ! -d /mnt/record ]; then
    mkdir /mnt/records
fi
chmod -R 777 /mnt
apt-get install -y nfs-common

# Mount Host(synology) Shared folders
umount /mnt/records/
mount -t nfs 192.168.86.100:/volume1/records /mnt/records/

# Add the following in /etc/fstab
if ! grep -q records /etc/fstab;
then
    echo 192.168.86.100:/volume1/records /mnt/records nfs defaults 0 0 >> /etc/fstab
fi

# Install required packages
apt-get install -y curl
curl -sL https://deb.nodesource.com/setup_16.x | sudo bash -
apt-get install -y unzip git cmake g++ build-essential pcscd libpcsclite-dev libccid pcsc-tools automake autoconf autoconf-doc libtool libtool-doc nodejs npm sqlite3 ffmpeg
npm install -y pm2 -g

# Tuner Driver
# unzip -o -d ${HOME}/tv $(dirname $0)/tv/PX-S1UD_driver_Ver.1.0.1.zip
# cp ${HOME}/tv/PX-S1UD_driver_Ver.1.0.1/x64/amd64/isdbt_rio.inp /lib/firmware/
unzip -o -d ${HOME}/tv $(dirname $0)/tv/ubuntu20.04.2_PX-S1UD_Driver.zip
cp ${HOME}/tv/ubuntu20.04.2_PX-S1UD_Driver/s270-firmware/isdbt_rio.inp /lib/firmware/

# Rec App
# tar --overwrite -xvzf $(dirname $0)/tv/recdvb-1.3.1.tgz -C ${HOME}/tv
if [ ! -d ${HOME}/recdvb-dogeel ]; then
    git clone https://github.com/dogeel/recdvb.git ${HOME}/recdvb-dogeel
fi
if [ ! -d ${HOME}/recdvb-qpe ]; then
    git clone https://github.com/qpe/recdvb.git ${HOME}/recdvb-qpe
fi
cd ${HOME}/recdvb-dogeel
./autogen.sh
./configure --enable-b25
make 
make install
cd $(dirname $0)

# libarib25
if [ ! -d ${HOME}/libarib25 ]; then
    git clone https://github.com/stz2012/libarib25.git ${HOME}/libarib25
fi
cd ${HOME}/libarib25
git pull
cmake .
make
make install
cd $(dirname $0)

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

# EPGStation
if [ ! -d ${HOME}/EPGStation ]; then
    git clone https://github.com/l3tnun/EPGStation.git ${HOME}/EPGStation
fi
cd ${HOME}/EPGStation
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
cd $(dirname $0)
