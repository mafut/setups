This is personal notes to keep setup script for cloud instance and Raspberry Pi to run some applicatioins.

# Proxy (squid)

Main target user is who lives outside of Japan and expects to browse restricted sites and watch ondemand TV (e.g. TVer, Amazon Prime Viode and even Netflix). Even non-restricted site would have better performance by avoiding unnecessary routing. Both setup scripts support one host name that doesn't require password to access. If the host is for your home ip address by DDNS, no password from home.

### proxy/setup.sh
This is shell script to setup proxy on Synology or cloud VM server like Azure, AWS or VPS. From my experience, I don't recommend to use Azure or AWS because they count traffic volume and it will exceed even free tier.


# TV Recorder with PX-S1UD

### tv/setup_ubuntu.sh (Incompleted)

This is for ubuntu 22.04 LTS.


# PHP Development with Code-Server

### setup_lamp.sh

This script set up Linux-Apache-MySQL-PHP (LAMP) site with Code-Server on Ubuntu. This also supports multi-user and expects the following as the result.

Url | What you can
-|-
http://[user].[your_domain]/ | Apache default page as default. This is used for certbot as well.
https://[user].[your_domain]/ | Your PHP-MySQL site on HTTPS.
https://[user].[your_domain]/content/ | For static contents.
https://[user].[your_domain]/vscode/ | Code-Server to develop your PHP-MySQL site.

Request host doesn't match with configured server_name of /etc/nginx/sites-enabled/, first configuration will be used.
If you'd like to use specific config, add "default_server" in listen directive like "listen 443 ssl default_server".

## Quick Steps
1. Create new user and login
    ```
    sudo adduser [user]
    sudo usermod -G sudo [user]
    su [user]
    ```
2. Get the latest source
    ```
    git clone https://github.com/mafut/setupscripts.git
    ```
3. Setup a site with self-signed cert
    ```
    touch ./setup_lamp.sh.conf
    sudo ./setup_lamp.sh
    ```
5. Issue a certificate
    ```
    sudo certbot certonly --agree-tos --webroot -w /var/www/html/ -d [user].[your_domain]
    ```
6. Edit setup_lamp.sh.conf
7. Setup with real cert
    ```
    sudo ./setup_lamp.sh
    ```

### dev_ubuntu.sh.conf with real cert
```
DOCPATH_ROOT=/home/[user]/php_app
DOCPATH_HTTP=/var/www/html
DOCPATH_CONTENT=/home/[user]/static_content
ENABLE_HTTP=true
ENABLE_CONTENT=true
ENABLE_VSCODE=true
NGINX_CERT_PATH=/etc/letsencrypt/live/[user].[your_domain]
NGINX_DEFAULT=true
APACHE_PORT=8081
CODESERVER_PASS=password
CODESERVER_PORT=8082
```

# Raspberry Pi 4

### setup_RPi4.sh
### setup_RPi4_Display.sh

This script setup Raspberry Pi 4 to run one or more of above. Expected OS is ubuntu 22.04.
