# Proxy (squid)

Main target user is who lives outside of Japan and expects to browse restricted sites and watch ondemand TV (e.g. TVer, Amazon Prime Viode and even Netflix). Even non-restricted site would have better performance by avoiding unnecessary routing. Both setup script supports one host name that doesn't require password to access. If the host is for your home ip address by DDNS, no password from home.

### proxy_synology.sh

This is just shell script to setup proxy using Docker on synology . 

### proxy_ubuntu22.sh

This is just shell script to setup proxy on cloud VM server like Azure, AWS or VPS.


# TV Recorder with PX-S1UD
### tv_ubuntu22_synology.sh

This is for ubuntu 22.04 LTS on Synology VM.

### tv_ubuntu22_raspberrypi4.sh

This is for ubuntu 22.04 LTS on Raspberry Pi 4


# PHP Development with Code-Server
### dev_ubuntu20.sh

This script setups Apache-PHP-MySQL site with Code-Server. This also supports multi-user and expects the following as the result.

Url | What you can
-|-
http://[user].your_domain/ | Apache default. This is used for certbot as well.
https://[user].your_domain/ | Your PHP-MySQL site.
https://[user].your_domain/vscode/ | Code-Server to develop your PHP-MySQL site.

## Quick Steps
1. Create new user and login
    1. sudo adduser [user]
    2. sudo usermod -G sudo [user]
    3. su [user]
2. Configure SSH
    1. ssh-keygen
    2. Register id_rsa.pub to github
    3. (Option) Add yubikey's public cert to authorized_keys
3. Get the latest source
    * git clone git@github.com:mafut/setupscripts.git
4. Setup a site with self-signed cert
    * sudo ./dev_ubuntu20.sh [your_site_folder] password 8081 8082
5. Issue a certificate
    * sudo certbot certonly --agree-tos --webroot -w /var/www/html/ -d [user].your_domain
6. Setup with real cert
    * sudo ./dev_ubuntu20.sh [your_site_folder] password 8081 8082 /etc/letsencrypt/live/[user].[your_domain]
