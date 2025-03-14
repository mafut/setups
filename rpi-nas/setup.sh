#!/bin/bash
DIR_COMMON=$(
    cd $(dirname $0)
    cd ../rpi-common/
    pwd
)
source ${DIR_COMMON}/setup64-legacy.sh

# https://www.waveshare.com/wiki/CM4-NAS-Double-Deck
# [USB] Add "dtoverlay=dwc2,dr_mode=host" to config.txt
# [RTC] Add "dtoverlay=i2c-rtc,pcf85063a" to config
# [SPI] Enable "dtparam=spi=on"
# [LCD] Disable "dtoverlay=vc4-kms-v3d"
# [LCD] Disable "max_framebuffers=2"

# https://www.waveshare.com/wiki/2inch_LCD_Module
# Raspberry Pi OS Legacy Only
sudo apt-get install cmake -y
cd ~
wget https://files.waveshare.com/upload/1/18/Waveshare_fbcp.zip
unzip Waveshare_fbcp.zip
cd Waveshare_fbcp/
mkdir build
cd build
cmake -DSPI_BUS_CLOCK_DIVISOR=20 -DWAVESHARE_2INCH_LCD=ON -DBACKLIGHT_CONTROL=ON -DSTATISTICS=0 ..
sudo make -j
cp ~/Waveshare_fbcp/build/fbcp /usr/local/bin/fbcp
# Add fbcp& before exit 0 in /etc/rc.local
# Add to /boot/config.txt
hdmi_force_hotplug=1
hdmi_cvt=640 480 60 1 0 0 0
hdmi_group=2
hdmi_mode=1
hdmi_mode=87
display_rotate=0


# raspi-gpio
# PWR: (GPIO26)
# USER: (GPIO20)
