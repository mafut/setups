# README

This is personal notes to keep setup script for cloud instance and Raspberry Pi to run some applications.

## Proxy (squid)

Main target user is who lives outside of Japan and expects to browse restricted sites and watch ondemand TV (e.g. TVer, Amazon Prime Video and even Netflix). Even non-restricted site would have better performance by avoiding unnecessary routing. Both setup scripts support one host name that doesn't require password to access. If the host is for your home ip address by DDNS, no password from home.

### proxy/setup.sh
This is shell script to setup proxy on Synology or cloud VM server like Azure, AWS or VPS. From my experience, I don't recommend to use Azure or AWS because they count traffic volume and it will exceed even free tier.


## PHP Development with Code-Server

### lamp/setup.sh

This script set up Linux-Apache-MySQL-PHP (LAMP) site with Code-Server on Ubuntu. This also supports multi-user and expects the following as the result.

Url | What you can
-|-
http://[user].[your_domain]/ | Apache default page as default. This is used for certbot as well.
https://[user].[your_domain]/ | Your PHP-MySQL site on HTTPS.
https://[user].[your_domain]/content/ | For static contents. location "/content/" can change.
https://[user].[your_domain]/vscode/ | Code-Server to develop your PHP-MySQL site. location "/vscode/" can change.

Request host doesn't match with configured server_name of /etc/nginx/sites-enabled/, first configuration will be used.
If you'd like to use specific config, add "default_server" in listen directive like "listen 443 ssl default_server".

### Quick Steps
1. Create new user and login
    ```
    sudo adduser [user]
    sudo usermod -G sudo [user]
    su [user]
    ```
2. Get the latest source
    ```
    git clone https://github.com/mafut/setupscripts.git
    cd setupscripts/lamp
    touch ./setup.sh.conf
    ```
3. Issue a certificate by Let's encrypt
    ```
    sudo certbot certonly --agree-tos --webroot -w /var/www/html/ -d [user].[your_domain]
    ```
4. Edit setup.sh.conf
5. Run setup.sh
    ```
    sudo ./setup.sh
    ```

### setup.sh.conf

Example Case
* Let's Encrypt cert
* Every hour sync
* Open 8080 for another purpose

```
DOCPATH_HTTPS=/home/[user]/php_app
DOCPATH_HTTP=/var/www/html

PORT_HTTPS=8081
PORT_VSCODE=8082

ENABLE_VSCODE=true

NGINX_DEFAULT_CERTPATH=/etc/letsencrypt/live/www.hogehoge.com
NGINX_CERTPATH=/etc/letsencrypt/live/user.hogehoge.com
NGINX_FQDN=(
    "www.hogehoge.com"
    "user.hogehoge.com"
)
APACHE_REWRITE_DOMAIN=www.hogehoge.com
PHP_VER=5.6

CODESERVER_VER=4.23.1
CODESERVER_PASS=password

ALLOWED_PORTS=(8080)

CRON_JOBS=(
    "0 * * * * /bin/sh -c 'cd ${DOCPATH_ROOT} && /usr/bin/git fetch --all && /usr/bin/git checkout . && /usr/bin/git clean -df && /usr/bin/git reset --hard origin/master && /usr/bin/git pull origin master'"
    "0 * * * * /bin/sh -c 'cd ${DOCPATH_STATIC} && /usr/bin/git fetch --all && /usr/bin/git checkout . && /usr/bin/git clean -df && /usr/bin/git reset --hard origin/master && /usr/bin/git pull origin master'"
)
```

## Raspberry Pi 4

These scripts setup Raspberry Pi 4 to run one or more of above. Expected OS is ubuntu 22.04.

### RPi4/setup_waveshare-4.3-dsi-lcd.sh

### RPi4/setup_gpi-case-2.sh


## TV Recorder with PX-S1UD

### tv/setup.sh (Incompleted)

This is for ubuntu 22.04 LTS.
