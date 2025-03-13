#!/bin/bash
DIR_COMMON=$(
    cd $(dirname $0)
    cd ../rpi-common/
    pwd
)
source ${DIR_COMMON}/setup64.sh


# https://www.waveshare.com/wiki/CM4-NAS-Double-Deck
# [USB] Add "dtoverlay=dwc2,dr_mode=host" to config.txt
# [RTC] ADD "dtoverlay=i2c-rtc,pcf85063a" to config

# Enable SPI for Display
raspi-config nonint do_spi 0
