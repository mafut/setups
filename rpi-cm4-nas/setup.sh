#!/bin/bash
DIR_COMMON=$(
    cd $(dirname $0)
    cd ../rpi-common/
    pwd
)
source ${DIR_COMMON}/setup64.sh


# https://www.waveshare.com/wiki/CM4-NAS-Double-Deck
# [USB] Add "dtoverlay=dwc2,dr_mode=host" to config.txt
# [RTC] Add "dtoverlay=i2c-rtc,pcf85063a" to config
# [SPI] Enable "dtparam=spi=on"

# https://www.waveshare.com/wiki/2inch_LCD_Module
# Raspberry Pi OS Legacy Only

# raspi-gpio
# PWR: (GPIO26)
# USER: (GPIO20)
