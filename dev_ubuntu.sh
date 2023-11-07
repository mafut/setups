#!/bin/bash

# Load variables from dev_ubuntu.sh.conf
CONF=$1
if [ -z "${CONF}" ]; then
    CONF=$0.conf
fi
if [ ! -e ${CONF} ]; then
    echo "Usage: this_script.sh [conf=this_script.sh.conf]"
    exit 1
fi

source ${CONF}
source $0.default.conf

# Trim a trailing slash
DOCPATH_ROOT=${DOCPATH_ROOT%/}
DOCPATH_HTTP=${DOCPATH_HTTP%/}
DOCPATH_CONTENT=${DOCPATH_CONTENT%/}

# NGINX_CERT_PATH
if [ -z "${NGINX_CERT_PATH}" ]; then
    NGINX_CERT_PATH=$(
        cd $(dirname $0)/cert
        pwd
    )
fi
NGINX_CERT_PATH=${NGINX_CERT_PATH%/}

# Valuables from OS/environment
if [ -f /etc/os-release ]; then
    source /usr/lib/os-release
    case $VERSION_ID in
    20.04) OS_PHP_VER=7.4 ;;
    22.04) OS_PHP_VER=8.1 ;;
    *) exit 1 ;;
    esac
else
    echo "/etc/os-release is not exist."
    exit 1
fi

ARCH=$(arch)
case $ARCH in
aarch64) OS_ARCH=arm64 ;;
*) OS_ARCH=amd64 ;;
esac

USERNAME=$SUDO_USER
if [ -z "${USERNAME}" ]; then
    echo "Can't get User Name"
    exit 1
fi

# Configuration
cat <<EOF
Nginx
+-- Conf: /etc/nginx/sites-available/${USERNAME}.conf
+-- Default for *.domain: ${NGINX_DEFAULT}
|
+-- http://${USERNAME}.domain:80
|   +-- Enabled:${ENABLE_HTTP}
|   +-- Path:${DOCPATH_HTTP}
|
+-- https://${USERNAME}.domain:443
    +-- SSL:${NGINX_CERT_PATH}
    |
    +-- /
    |   +-- Path: ${DOCPATH_ROOT}
    |   +-- Port: ${APACHE_PORT}
    |   +-- PHP: ${OS_PHP_VER}
    |   +-- Apache By: ${APACHE_USER}
    |   +-- Apache Log: ${APACHE_LOG}
    |   +-- MySQL By: ${MYSQL_USER}
    |   +-- MySQL Log: ${MYSQL_LOG}
    |
    +-- /content
    |   +-- Enabled: ${ENABLE_CONTENT}
    |   +-- Path: ${DOCPATH_CONTENT}
    |
    +-- /vscode
        +-- Enabled: ${ENABLE_VSCODE}
        +-- Port: ${CODESERVER_PORT}
        +-- Architecture: ${OS_ARCH}
        +-- Version: ${CODESERVER_VER}
        +-- Password: ${CODESERVER_PASS}
EOF
read -p "Hit enter if ok: "

# [Security] Skip password when sudo. The format is "${USERNAME} ALL=NOPASSWD: ALL"
if ! grep -q ${USERNAME} /etc/sudoers; then
    echo ${USERNAME} ALL=NOPASSWD: ALL >>/etc/sudoers
fi

# Stop Services at the first
systemctl disable --now nginx
systemctl disable --now apache2
systemctl disable --now mysql
systemctl disable --now code-server
systemctl disable --now code-server@${USERNAME}

# apt-get update/upgrade
# add-apt-repository ppa:ondrej/apache2 -y
apt-get -y --allow update
apt-get -y --allow upgrade

# Install packages
apt-get -y --allow install ufw wget zip unzip
apt-get -y --allow install certbot python3 python3-pip python-is-python3
apt-get -y --allow install logrotate logwatch nginx apache2 php php-gd php-mbstring php-mysql php-apcu php-soap libapache2-mod-php composer
apt-get -y --allow autoremove
python -m pip install --user virtualenv
a2enmod authz_groupfile
a2enmod headers
a2enmod rewrite
a2ensite ${USERNAME}

a2dismod ssl
a2dismod proxy
a2dismod proxy_http
a2dismod proxy_wstunnel
a2dissite default-ssl

# [Security] Setup Firewall
ufw disable
ufw --force reset
ufw default deny
ufw allow 22
ufw limit 22
ufw allow 80
ufw allow 443
ufw allow 8080 # Squid
ufw --force enable

# [Code-Server] Install
if [ ! -e ./code-server_${CODESERVER_VER}_${OS_ARCH}.deb ]; then
    curl -fOL https://github.com/coder/code-server/releases/download/v${CODESERVER_VER}/code-server_${CODESERVER_VER}_${OS_ARCH}.deb
    dpkg -i ./code-server_${CODESERVER_VER}_${OS_ARCH}.deb
fi

# [Code-Server] Reset Permission
mkdir -p /home/${USERNAME}/.local/share/code-server
chown -R ${USERNAME} /home/${USERNAME}/.local/
chgrp -R ${USERNAME} /home/${USERNAME}/.local/
find /home/${USERNAME}/.local/share/code-server -type d -exec chmod 755 {} \;
find /home/${USERNAME}/.local/share/code-server -type f -exec chmod 644 {} \;

mkdir -p /home/${USERNAME}/.config/code-server
chown -R ${USERNAME} /home/${USERNAME}/.config/
chgrp -R ${USERNAME} /home/${USERNAME}/.config/
find /home/${USERNAME}/.config/code-server -type d -exec chmod 755 {} \;
find /home/${USERNAME}/.config/code-server -type f -exec chmod 644 {} \;

# [Code-Server] Config
CONFIG=/etc/systemd/system/code-server@${USERNAME}.service
cat <<EOF >${CONFIG}
[Unit]
Description=code-server
After=apache2.service

[Service]
Type=simple
User=${USERNAME}
WorkingDirectory=/home/${USERNAME}
Restart=always
RestartSec=10

ExecStart=/usr/bin/code-server --host 127.0.0.1 --user-data-dir /home/${USERNAME}/.local/share/code-server
ExecStop=/bin/kill -s QUIT $MAINPID

[Install]
WantedBy=multi-user.target
EOF

CONFIG=/home/${USERNAME}/.config/code-server/config.yaml
cat <<EOF >${CONFIG}
bind-addr: 127.0.0.1:${CODESERVER_PORT}
auth: password
password: ${CODESERVER_PASS}
cert: false
user-data-dir: /home/${USERNAME}/.local/share/code-server
log: debug
EOF

# [logrotate] Main Config
CONFIG=/etc/logrotate.conf
cat <<EOF >${CONFIG}
weekly
rotate 10
create
missingok
include /etc/logrotate.d
EOF

# [logrotate] apache2
CONFIG=/etc/logrotate.d/apache2
cat <<EOF >${CONFIG}
/var/log/apache2/*.log {
    compress
    delaycompress
    notifempty
    create 0640 www-data root
    sharedscripts
    postrotate
            if invoke-rc.d apache2 status > /dev/null 2>&1; then \
                invoke-rc.d apache2 reload > /dev/null 2>&1; \
            fi;
    endscript
    prerotate
            if [ -d /etc/logrotate.d/httpd-prerotate ]; then \
                    run-parts /etc/logrotate.d/httpd-prerotate; \
            fi; \
    endscript
}
EOF

# [logrotate] mysql-server
CONFIG=/etc/logrotate.d/mysql-server
cat <<EOF >${CONFIG}
/var/log/mysql.log /var/log/mysql/*log {
    create 640 mysql mysql
    compress
    sharedscripts
    postrotate
            test -x /usr/bin/mysqladmin || exit 0
            MYADMIN="/usr/bin/mysqladmin --defaults-file=/etc/mysql/debian.cnf"
            if [ -z "$($MYADMIN ping 2>/dev/null)" ]; then
                if killall -q -s0 -umysql mysqld; then
                    exit 1
                fi
            else
                $MYADMIN flush-logs
            fi
    endscript
}
EOF

# [logrotate] nginx
CONFIG=/etc/logrotate.d/nginx
cat <<EOF >${CONFIG}
/var/log/nginx/*.log {
    compress
    delaycompress
    create 0640 www-data root
    sharedscripts
    prerotate
            if [ -d /etc/logrotate.d/httpd-prerotate ]; then \
                run-parts /etc/logrotate.d/httpd-prerotate; \
            fi \
    endscript
    postrotate
            invoke-rc.d nginx rotate >/dev/null 2>&1
    endscript
}
EOF

# [logwatch] Config
mkdir -p /etc/logwatch/conf
mkdir -p /var/cache/logwatch
CONFIG=/etc/logwatch/conf/logwatch.conf
cat <<EOF >${CONFIG}
TmpDir = /var/cache/logwatch
# Output = mail
Output = stdout
Format = text
Encode = none
Range = yesterday
Detail = High
Service = All
# MailTo = root
# MailFrom = Logwatch
# mailer = "/usr/sbin/sendmail -t"
EOF

# [MySQL] Config /etc/mysql/conf.d/my.cnf
# default my.cnf loads from the following
# /etc/mysql/conf.d/
# /etc/mysql/mysql.conf.d/
CONFIG=/etc/mysql/conf.d/my.cnf
if [ -f ${CONFIG} ]; then
    cp -f ${CONFIG} ${CONFIG}.bak
fi
cat <<EOF >${CONFIG}
[mysqld]
# When reset root password
# skip-grant-tables

character-set-server = utf8mb4
# collation-server = utf8mb4_general_ci
collation_server = utf8mb4_ja_0900_as_cs

# Timezone
default-time-zone = SYSTEM
log_timestamps = SYSTEM

basedir   = /var/lib/mysql
datadir   = /var/lib/mysql-files
pid-file  = /var/run/mysqld/mysqld.pid
socket    = /var/run/mysqld/mysqld.sock
log-error = ${MYSQL_LOG}/error.log
lc_messages_dir = /usr/share/mysql-8.0/english

performance-schema = 0
local-infile = 0
mysqlx = 0
bind-address = 127.0.0.1
symbolic-links = 0
explicit_defaults_for_timestamp = 0
default-storage-engine=innodb
default_password_lifetime = 0
log_bin_trust_function_creators = 1
sql-mode = "TRADITIONAL,ALLOW_INVALID_DATES,NO_ENGINE_SUBSTITUTION"

innodb_dedicated_server = 1
innodb_log_buffer_size = 64M
innodb_read_io_threads = 12
innodb_write_io_threads = 12
innodb_stats_on_metadata = 0
innodb_file_per_table = 1

table_definition_cache = 65536
table_open_cache = 65536

tmp_table_size = 128M
max_heap_table_size = 128M

read_buffer_size = 256K
join_buffer_size = 512K
sort_buffer_size = 512K
read_rnd_buffer_size = 512K

[mysql]
auto-rehash
default-character-set = utf8mb4

[mysqldump]
default-character-set = utf8mb4
EOF

# [MySQL] Install
if [ ! -e ${MYSQL_REPO} ]; then
    curl -fOL https://dev.mysql.com/get/${MYSQL_REPO}
    dpkg -i ./${MYSQL_REPO}
    apt-get -y --allow install mysql-server
fi

# [MySQL] Data Permission
chown mysql:${MYSQL_USER} /var/lib/mysql
chown mysql:${MYSQL_USER} /var/lib/mysql-files
chown mysql:${MYSQL_USER} ${MYSQL_LOG}

chmod 750 /var/lib/mysql
chmod 750 /var/lib/mysql-files
chmod 750 ${MYSQL_LOG}

usermod -d /var/lib/mysql/ ${MYSQL_USER}
mysqld --initialize-insecure --user=${MYSQL_USER}

# [MySQL] Resolve warning at start
dpkg-divert --local --rename --add /sbin/initctl
if [ ! -e /sbin/initctl ]; then
    ln -s /bin/true /sbin/initctl
fi

# [Apache] Reset Permission: User(6)/UserGroup(4)/Other(4)
chown -R ${USERNAME} ${DOCPATH_ROOT}/
chgrp -R ${USERNAME} ${DOCPATH_ROOT}/
find ${DOCPATH_ROOT}/ -type d -exec chmod 755 {} \;
find ${DOCPATH_ROOT}/ -type f -exec chmod 644 {} \;

mkdir -p ${DOCPATH_HTTP}/setting/
chown -R ${USERNAME} ${DOCPATH_HTTP}/setting/
chgrp -R ${USERNAME} ${DOCPATH_HTTP}/setting/
find ${DOCPATH_HTTP}/setting/ -type d -exec chmod 755 {} \;
find ${DOCPATH_HTTP}/setting/ -type f -exec chmod 644 {} \;

mkdir -p ${APACHE_LOG}
chown -R ${USERNAME} ${APACHE_LOG}
chgrp -R ${USERNAME} ${APACHE_LOG}
find ${APACHE_LOG} -type d -exec chmod 755 {} \;
find ${APACHE_LOG} -type f -exec chmod 644 {} \;

# [Apache] User to Apache
usermod -g ${APACHE_USER} ${USERNAME}
chown -R ${APACHE_USER} ${DOCPATH_ROOT}/application/logs/
chown -R ${APACHE_USER} ${DOCPATH_ROOT}/application/cache/
chown -R ${APACHE_USER} ${DOCPATH_ROOT}/images/
chown -R ${APACHE_USER} ${DOCPATH_ROOT}/setting/
chown -R ${APACHE_USER} ${DOCPATH_HTTP}/setting/
chown -R ${APACHE_USER} ${APACHE_LOG}

# [Apache] Configure Permission
find ${DOCPATH_HTTP}/setting/ -type f -exec chmod 600 {} \;
find ${DOCPATH_ROOT}/setting/ -type f -exec chmod 600 {} \;
find ${DOCPATH_ROOT}/ -name .htaccess -exec chmod 644 {} \;
find ${DOCPATH_ROOT}/ -name index.html -exec chmod 644 {} \;
find ${DOCPATH_ROOT}/setup/ -name \*.sh -exec chmod 755 {} \;

# [Apache] Configure http
CONFIG=/etc/apache2/sites-available/000-default.conf
cat <<EOF >${CONFIG}
AcceptFilter http none
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    ServerName localhost:80

    LogLevel warn
    ErrorLog ${APACHE_LOG}/error.log
    CustomLog ${APACHE_LOG}/access.log combined

    DocumentRoot ${DOCPATH_HTTP}
    <Directory ${DOCPATH_HTTP}>
        Options All
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF
rm -f /etc/apache2/sites-enabled/000-default.conf
ln -s /etc/apache2/sites-available/000-default.conf /etc/apache2/sites-enabled/000-default.conf

CONFIG=/etc/apache2/sites-available/${USERNAME}.conf
cat <<EOF >${CONFIG}
AcceptFilter http none
Listen ${APACHE_PORT}
<VirtualHost *:${APACHE_PORT}>
    ServerAdmin webmaster@localhost
    ServerName localhost:${APACHE_PORT}

    LogLevel warn
    ErrorLog ${APACHE_LOG}/error.log
    CustomLog ${APACHE_LOG}/access.log combined

    DocumentRoot ${DOCPATH_ROOT}
    <Directory ${DOCPATH_ROOT}>
        Options All
        AllowOverride All
        Require all granted
    </Directory>

    Alias /application/views ${DOCPATH_ROOT}/application/views
    <Directory ${DOCPATH_ROOT}/application/views>
        Options All
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF
rm -f /etc/apache2/sites-enabled/${USERNAME}.conf
ln -s /etc/apache2/sites-available/${USERNAME}.conf /etc/apache2/sites-enabled/${USERNAME}.conf

# [Php] Set display_errors, display_startup_errors as ON
CONFIG=/etc/php/${OS_PHP_VER}/apache2/php.ini
cp -f ${CONFIG} ${CONFIG}.bak
sh -c "sed \"s|display_errors = Off|display_errors = On|g\" ${CONFIG}.bak > ${CONFIG}"
cp -f ${CONFIG} ${CONFIG}.bak
sh -c "sed \"s|display_startup_errors = Off|display_startup_errors = On|g\" ${CONFIG}.bak > ${CONFIG}"
cp -f ${CONFIG} ${CONFIG}.bak
sh -c "sed \"s|;extension=php_soap.dll|extension=php_soap.dll|g\" ${CONFIG}.bak > ${CONFIG}"

# [Nginx] Configure https
rm -f /etc/nginx/sites-enabled/default

# [] is not needed in if. Format is 'if "${boolean}"''
if "${NGINX_DEFAULT}"; then
    NGINX_LISTEN='listen 443 ssl default_server;'
else
    NGINX_LISTEN='listen 443 ssl;'
fi

CONFIG=/etc/nginx/sites-available/${USERNAME}
cat <<EOF >${CONFIG}
server {
    ${NGINX_LISTEN}
    server_name ${USERNAME}.*;

    ssl_certificate ${NGINX_CERT_PATH}/fullchain.pem;
    ssl_certificate_key ${NGINX_CERT_PATH}/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:${APACHE_PORT}/;
        proxy_set_header Host \$host;
        proxy_set_header Accept-Encoding gzip;
    }

    location /content {
        autoindex on;
        root ${DOCPATH_CONTENT}
    }

    location /vscode/ {
        proxy_pass http://127.0.0.1:${CODESERVER_PORT}/;
        proxy_set_header Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection upgrade;
        proxy_set_header Accept-Encoding gzip;
    }
}
EOF
rm -f /etc/nginx/sites-enabled/${USERNAME}
ln -s /etc/nginx/sites-available/${USERNAME} /etc/nginx/sites-enabled/${USERNAME}

# Add auto-start user instance
loginctl enable-linger ${USERNAME}

# Add auto-start and start services
systemctl enable --now nginx
systemctl enable --now code-server@${USERNAME}
systemctl enable --now apache2
systemctl enable --now mysql

# [Cron] Schedule to pull
CONFIG=${DOCPATH_ROOT}/setting/crontab.bak
cat <<EOF >${CONFIG}
# */5 * * * * /bin/sh -c 'cd ${DOCPATH_ROOT} && /usr/bin/git fetch --all && /usr/bin/git checkout . && /usr/bin/git clean -df && /usr/bin/git reset --hard origin/master && /usr/bin/git pull origin master'
*/5 * * * * /bin/sh -c 'cd ${DOCPATH_ROOT} && /usr/bin/git fetch --all && /usr/bin/git pull origin master'
EOF
crontab -u ${USERNAME} ${DOCPATH_ROOT}/setting/crontab.bak

# Manual setup
cat <<EOF
[MySQL] Remove root password
1. Enable "skip-grant-tables" in /etc/mysql/conf.d/my.cnf
2. sudo systemctl restart mysql
3. Reset
  use mysql;
  update user set authentication_string="" where User='root';
  update user set plugin="mysql_native_password" where User='root';
  flush privileges;
4. Disable "skip-grant-tables" in /etc/mysql/conf.d/my.cnf
5. sudo systemctl restart mysql

[MySQL] Add root password for Production
sudo mysql_secure_installation

[SSH] Cert auth instead of password
1. Add id_rsa.pub to /home/${USERNAME}/.ssh/authorized_keys. 
2. Confirm if /etc/ssh/sshd_config allows rsa auth
  PubkeyAuthentication        yes
  RSAAuthentication           yes
  AuthorizedKeysFile          .ssh/authorized_keys
3. sudo systemctl restart sshd
4. Confirm if "ssh -i id_rsa ${USERNAME}@[hostname]" works
5. Confirm if /etc/ssh/sshd_config doesn't allow password auth
  PasswordAuthentication      no
6. sudo systemctl restart sshd
EOF
