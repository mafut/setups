#!/bin/bash

DIR_SELF=$(
    cd $(dirname $0)
    pwd
)

#region Variables

CONF=$1
if [ -z "${CONF}" ]; then
    # Load from default if no input
    CONF=$0.conf
fi

if [ ! -e ${CONF} ]; then
    echo "Usage: sudo setup_lamp.sh [conf=setup_lamp.sh.conf]"
    echo "Run \"touch setup_lamp.sh.conf\" for first run. This is needed action to avoid accidental run."
    exit 1
fi

source ${CONF}
source $0.default.conf

# Trim a trailing slash from path
DOCPATH_ROOT=${DOCPATH_ROOT%/}
DOCPATH_HTTP=${DOCPATH_HTTP%/}
DOCPATH_STATIC=${DOCPATH_STATIC%/}
LOCATION_STATIC=${LOCATION_STATIC%/}
LOCATION_VSCODE=${LOCATION_VSCODE%/}

# NGINX_CERT_PATH
if [ -z "${NGINX_CERT_PATH}" ]; then
    NGINX_CERT_PATH=${DIR_SELF}/cert
fi
NGINX_CERT_PATH=${NGINX_CERT_PATH%/}

# OS_ARCH
ARCH=$(arch)
case $ARCH in
aarch64) OS_ARCH=arm64 ;;
*) OS_ARCH=amd64 ;;
esac

# USERNAME
USERNAME=$SUDO_USER
if [ -z "${USERNAME}" ]; then
    echo "Can't get User Name"
    exit 1
fi

# Configuration/Data location
# MySQL: my.cnf is loaded from /etc/mysql/conf.d/ -> /etc/mysql/mysql.conf.d/
CONFIG_OS_NGINX=/etc/nginx/nginx.conf
CONFIG_OS_APACHE=/etc/apache2/apache2.conf
CONFIG_OS_MYSQL=/etc/mysql/conf.d/my.cnf
CONFIG_OS_LOGROTATION=/etc/logrotate.conf

DIR_CONFIG_LOGROTATION=/etc/logrotate.d
DIR_CONFIG_LOGWATCH=/etc/logwatch/conf
DIR_CONFIG_CODESERVER=/home/${USERNAME}/.config/code-server
DIR_DATA_LOGWATCH=/var/cache/logwatch
DIR_DATA_CODESERVER=/home/${USERNAME}/.local/share/code-server

mkdir -p ${DIR_CONFIG_LOGROTATION}
mkdir -p ${DIR_CONFIG_LOGWATCH}
mkdir -p ${DIR_CONFIG_CODESERVER}
mkdir -p ${DIR_DATA_LOGWATCH}
mkdir -p ${DIR_DATA_CODESERVER}
mkdir -p ${NGINX_LOG}
mkdir -p ${APACHE_LOG}
mkdir -p ${MYSQL_LOG}

CONFIG_LOGROTATION_APACHE=${DIR_CONFIG_LOGROTATION}/apache2
CONFIG_LOGROTATION_MYSQL=${DIR_CONFIG_LOGROTATION}/mysql-server
CONFIG_LOGROTATION_NGINX=${DIR_CONFIG_LOGROTATION}/nginx
CONFIG_LOGWATCH=${DIR_CONFIG_LOGWATCH}/logwatch.conf
CONFIG_CODESERVER_INSTALLER=code-server_${CODESERVER_VER}_${OS_ARCH}.deb
CONFIG_CODESERVER=${DIR_CONFIG_CODESERVER}/config.yaml
CONFIG_VSCODE=${DIR_DATA_CODESERVER}/User/settings.json
CONFIG_NGINX_DEFAULT=/etc/nginx/sites-available/default
CONFIG_NGINX_USER=/etc/nginx/sites-available/${USERNAME}
CONFIG_APACHE_DEFAULT=/etc/apache2/sites-available/000-default.conf
CONFIG_APACHE_USER=/etc/apache2/sites-available/${USERNAME}.conf

#endregion

#region Config confirmation

cat <<EOF
[Structure]
+-- http://${USERNAME}.domain:80
|   +-- /
|       +-- Visiable: ${ENABLE_HTTP}
|       +-- Path: ${DOCPATH_HTTP}
|       +-- Config: ${CONFIG_APACHE_DEFAULT}
|       +-- App/Port: Apache:80 (Fixed and shared across users)
|
+-- https://${USERNAME}.domain:443
|   +-- Base Config: ${CONFIG_OS_NGINX}
|   +-- User Config: ${CONFIG_NGINX_USER} (Default: ${NGINX_DEFAULT})
|   +-- SSL:${NGINX_CERT_PATH}
|   |
|   +-- /
|   |   +-- Visiable: true (Fxied)
|   |   +-- Path: ${DOCPATH_ROOT}
|   |   +-- Config: ${CONFIG_APACHE_USER}
|   |   +-- App/Port: Apache:${APACHE_PORT}
|   |   +-- PHP: ${PHP_VER}
|   |   +-- MySQL Config: ${CONFIG_OS_MYSQL}
|   |
|   +-- ${LOCATION_STATIC}
|   |   +-- Visiable: ${ENABLE_STATIC}
|   |   +-- Path: ${DOCPATH_STATIC}
|   |   +-- Config: ${CONFIG_NGINX_USER}
|   |   +-- App/Port: Nginx:443
|   |
|   +-- ${LOCATION_VSCODE}
|       +-- Visiable: ${ENABLE_VSCODE}
|       +-- Path: ${DIR_DATA_CODESERVER}
|       +-- Config Code-Server: ${CONFIG_CODESERVER}
|       +-- Config VS Code: ${CONFIG_VSCODE}
|       +-- App/Port: Code-Server:${CODESERVER_PORT}
|       +-- Installer: ${CONFIG_CODESERVER_INSTALLER}
|       +-- Password: ${CODESERVER_PASS}
|
+-- https://${USERNAME}.domain:XXXX
    +-- Allowed Ports: ${ALLOWED_PORTS[*]}

[User]
Unix: ${USERNAME}
Nginx: ${APACHE_USER}
Apache: ${APACHE_USER}
MySQL: ${MYSQL_USER}

[Log]
Nginx: ${NGINX_LOG}
Apache: ${APACHE_LOG}
MySQL: ${MYSQL_LOG}
LogWatch: ${DIR_DATA_LOGWATCH}

[VS Code Extensions]
${CODESERVER_EXTS[*]}

EOF
read -p "Hit enter if ok: "

#endregion

#region Base Setup

# [Base Setup] Skip password when sudo. The format is "${USERNAME} ALL=NOPASSWD: ALL"
if ! grep -q ${USERNAME} /etc/sudoers; then
    echo ${USERNAME} ALL=\(ALL\) NOPASSWD:ALL >>/etc/sudoers
fi

# [Base Setup] Reset user primary/secondary group
usermod -g ${USERNAME} ${USERNAME}
usermod -G ${APACHE_USER} ${USERNAME}

# [Base Setup] Stop Services at the first
systemctl disable --now nginx
systemctl disable --now apache2
systemctl disable --now mysql
systemctl disable --now code-server
systemctl disable --now code-server@${USERNAME}

# [Base Setup] Install packages
add-apt-repository ppa:ondrej/php -y
apt-get -y update
apt-get -y upgrade
apt-get -y install ufw wget zip unzip jq moreutils
apt-get -y install certbot python3 python3-pip python-is-python3
apt-get -y install ca-certificates apt-transport-https software-properties-common lsb-release
apt-get -y install logrotate logwatch nginx apache2 composer
apt-get -y install php8.2 libapache2-mod-php8.2 php8.2-apcu php8.2-cli php8.2-common php8.2-gd php8.2-intl php8.2-mbstring php8.2-mysql php8.2-soap
apt-get -y install php8.1 libapache2-mod-php8.1 php8.1-apcu php8.1-cli php8.1-common php8.1-gd php8.1-intl php8.1-mbstring php8.1-mysql php8.1-soap
apt-get -y install php7.4 libapache2-mod-php7.4 php7.4-apcu php7.4-cli php7.4-common php7.4-gd php7.4-intl php7.4-mbstring php7.4-mysql php7.4-soap
apt-get -y autoremove

update-alternatives --list php
update-alternatives --set php /usr/bin/php${PHP_VER}

a2enmod authz_groupfile
a2enmod headers
a2enmod rewrite

a2dismod ssl
a2dismod proxy
a2dismod proxy_http
a2dismod proxy_wstunnel

a2dissite default-ssl

# [Base Setup] Firewall
ufw disable
ufw --force reset
ufw default deny
ufw allow 22
ufw limit 22
ufw allow 443
if "${ENABLE_HTTP}"; then
    ufw allow 80
fi
for port in ${ALLOWED_PORTS[@]}; do
    ufw allow $port
done
ufw --force enable

#endregion

#region Code-Server

# [Code-Server] Install
if [ ! -e ${DIR_SELF}/download/${CONFIG_CODESERVER_INSTALLER} ]; then
    sudo -u ${USERNAME} curl -fL https://github.com/coder/code-server/releases/download/v${CODESERVER_VER}/${CONFIG_CODESERVER_INSTALLER} -o ${DIR_SELF}/download/${CONFIG_CODESERVER_INSTALLER}
    dpkg -i ${DIR_SELF}/download/${CONFIG_CODESERVER_INSTALLER}
fi

# [Code-Server] Reset Permission
chown -R ${USERNAME} /home/${USERNAME}/.local/
chgrp -R ${USERNAME} /home/${USERNAME}/.local/
find ${DIR_DATA_CODESERVER} -type d -exec chmod 755 {} \;
find ${DIR_DATA_CODESERVER} -type f -exec chmod 644 {} \;

chown -R ${USERNAME} /home/${USERNAME}/.config/
chgrp -R ${USERNAME} /home/${USERNAME}/.config/
find ${DIR_CONFIG_CODESERVER} -type d -exec chmod 755 {} \;
find ${DIR_CONFIG_CODESERVER} -type f -exec chmod 644 {} \;

# [Code-Server] Startup
cat <<EOF >/etc/systemd/system/code-server@${USERNAME}.service
[Unit]
Description=code-server
After=apache2.service

[Service]
Type=simple
User=${USERNAME}
WorkingDirectory=/home/${USERNAME}
Restart=always
RestartSec=10

ExecStart=/usr/bin/code-server --host 127.0.0.1 --user-data-dir ${DIR_DATA_CODESERVER}
ExecStop=/bin/kill -s QUIT $MAINPID

[Install]
WantedBy=multi-user.target
EOF

# [Code-Server] User Config
cat <<EOF >${CONFIG_CODESERVER}
bind-addr: 127.0.0.1:${CODESERVER_PORT}
auth: password
password: ${CODESERVER_PASS}
cert: false
user-data-dir: ${DIR_DATA_CODESERVER}
log: debug
EOF

# [Code-Server] Extensions
readonly INSTALLED=($(sudo -u ${USERNAME} code-server --list-extensions))
echo "Installed extensions:${INSTALLED[@]}"

installed() {
    for installed in ${INSTALLED[@]}; do
        if [[ $installed = ${1} ]]; then
            # true
            return 0
        fi
    done
    # false
    return 1
}

for extension in ${CODESERVER_EXTS[@]}; do
    if installed $extension; then
        echo "Already installed $extension"
    else
        sudo -u ${USERNAME} code-server --install-extension $extension
    fi
done

# Manually install extensions that code-server can't install from UI
# Save installing extensions in download folder
for vsix in ${DIR_SELF}/download/*.vsix; do
    [ -e "$vsix" ] || continue
    extname=$(basename "$vsix" | sed -E 's/(.+)-[0-9.]+\.vsix/\1/')
    if installed $extname; then
        echo "Already installed $extname ($vsix)"
    else
        sudo -u ${USERNAME} code-server --install-extension $vsix
    fi
done

# [Code-Server] Extension config
if [ ! -e ${CONFIG_VSCODE} ]; then
    sudo -u ${USERNAME} touch ${CONFIG_VSCODE}
fi
PHP_CS_FIXER_PHAR=${DIR_SELF}/download/php-cs-fixer.phar
if [ ! -e ${PHP_CS_FIXER_PHAR} ]; then
    sudo -u ${USERNAME} curl -fL https://cs.symfony.com/download/php-cs-fixer-v3.phar -o ${PHP_CS_FIXER_PHAR}
fi

# Explicit Folding
jq '.["editor.defaultFoldingRangeProvider"]|="zokugun.explicit-folding"' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '.["editor.foldingStrategy"]|="auto"' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '."[php]"."explicitFolding.rules"|=[]' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '."[php]"."explicitFolding.rules"+=[{"beginRegex":"(?:case|default)[^:]*:", "endRegex":"break;|(.)(?=case|default|\\})","foldLastLine":[true,false]}]' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '."[php]"."explicitFolding.rules"+=[{"beginRegex":"\\{", "middleRegex":"\\}[^}]+\\{", "endRegex":"\\}"}]' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '."[shellscript]"."explicitFolding.rules"|=[]' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '."[shellscript]"."explicitFolding.rules"+=[{"beginRegex":"#region", "endRegex":"#endregion", "autoFold":true}]' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '."[shellscript]"."explicitFolding.rules"+=[{"beginRegex":"\\{", "middleRegex":"\\}[^}]+\\{", "endRegex":"\\}"}]' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"

# php cs fixer "junstyle.php-cs-fixer"
jq '.["php-cs-fixer.executablePath"]|="'${PHP_CS_FIXER_PHAR}'"' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '.["php-cs-fixer.autoFixByBracket"]|=true' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '.["php-cs-fixer.autoFixBySemicolon"]|=true' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '.["php-cs-fixer.formatHtml"]|=true' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '.["php-cs-fixer.lastDownload"]|=0' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '.["php-cs-fixer.rules"]|=""' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '."[php]"."editor.defaultFormatter"|="junstyle.php-cs-fixer"' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"

# Render Line Endings
jq '.["editor.renderControlCharacters"]|=true' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '.["editor.renderWhitespace"]|="all"' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"

# Preference
jq '.["workbench.colorTheme"]|="Default Dark Modern"' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '.["git.autofetch"]|=false' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '.["git.confirmSync"]|=false' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '.["git.enableSmartCommit"]|=true' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '.["explorer.confirmDelete"]|=false' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '.["explorer.confirmDragAndDrop"]|=false' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"

jq --sort-keys '.' ${CONFIG_VSCODE} | sponge ${CONFIG_VSCODE}
chown ${USERNAME} ${CONFIG_VSCODE}
chgrp ${USERNAME} ${CONFIG_VSCODE}

#endregion

#region MySQL

# [MySQL] Config
if [ -f ${CONFIG_OS_MYSQL} ] && [ ! -f ${CONFIG_OS_MYSQL}.bak ]; then
    # Backup original
    cp -f ${CONFIG_OS_MYSQL} ${CONFIG_OS_MYSQL}.bak
fi
cat <<EOF >${CONFIG_OS_MYSQL}
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
if [ ! -e ${DIR_SELF}/download/${MYSQL_REPO} ]; then
    sudo -u ${USERNAME} curl -fL https://dev.mysql.com/get/${MYSQL_REPO} -o ${DIR_SELF}/download/${MYSQL_REPO}
    dpkg -i ${DIR_SELF}/download/${MYSQL_REPO}
    apt-get -y install mysql-server
fi

# [MySQL] Data Permission
chown ${MYSQL_USER}:${MYSQL_USER} /var/lib/mysql
chown ${MYSQL_USER}:${MYSQL_USER} /var/lib/mysql-files
chown ${MYSQL_USER}:${MYSQL_USER} ${MYSQL_LOG}

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

#endregion

#region PHP

# [Php] php.ini
PHP_VERS=(
    8.2
    8.1
    7.4
)
for phpver in "${PHP_VERS[@]}"; do
    CONFIG_OS_PHP=/etc/php/$phpver/apache2/php.ini

    if [ -f ${CONFIG_OS_PHP} ] && [ ! -f ${CONFIG_OS_PHP}.bak ]; then
        # Backup original
        cp -f ${CONFIG_OS_PHP} ${CONFIG_OS_PHP}.bak
    fi
    sed "s|display_errors = Off|display_errors = On|g" ${CONFIG_OS_PHP} | sponge ${CONFIG_OS_PHP}
    sed "s|display_startup_errors = Off|display_startup_errors = On|g" ${CONFIG_OS_PHP} | sponge ${CONFIG_OS_PHP}
    sed "s|;extension_dir = "./"|extension_dir = "./"|g" ${CONFIG_OS_PHP} | sponge ${CONFIG_OS_PHP}
    sed "s|;extension=php_soap.dll|extension=php_soap.dll|g" ${CONFIG_OS_PHP} | sponge ${CONFIG_OS_PHP}
    sed "s|;extension=curl|extension=curl|g" ${CONFIG_OS_PHP} | sponge ${CONFIG_OS_PHP}
    sed "s|;extension=mysqli|extension=mysqli|g" ${CONFIG_OS_PHP} | sponge ${CONFIG_OS_PHP}
done

#endregion

#region Apache

# [Apache] Reset Permission: User(6)/UserGroup(4)/Other(4)
# Ubuntu 22.04 the user dir has 750 permissions by default rather than 755.
chmod 755 /home/${USERNAME}/

chown -R ${USERNAME} ${DOCPATH_HTTP}/
chgrp -R ${USERNAME} ${DOCPATH_HTTP}/
find ${DOCPATH_HTTP}/ -type d -exec chmod 755 {} \;
find ${DOCPATH_HTTP}/ -type f -exec chmod 644 {} \;
find ${DOCPATH_HTTP}/ -name .htaccess -exec chmod 644 {} \;
find ${DOCPATH_HTTP}/ -name index.html -exec chmod 644 {} \;
find ${DOCPATH_HTTP}/ -name \*.sh -exec chmod 755 {} \;

chown -R ${USERNAME} ${DOCPATH_ROOT}/
chgrp -R ${USERNAME} ${DOCPATH_ROOT}/
find ${DOCPATH_ROOT}/ -type d -exec chmod 755 {} \;
find ${DOCPATH_ROOT}/ -type f -exec chmod 644 {} \;
find ${DOCPATH_ROOT}/ -name .htaccess -exec chmod 644 {} \;
find ${DOCPATH_ROOT}/ -name index.html -exec chmod 644 {} \;
find ${DOCPATH_ROOT}/ -name \*.sh -exec chmod 755 {} \;

chown -R ${USERNAME} ${DOCPATH_STATIC}/
chgrp -R ${USERNAME} ${DOCPATH_STATIC}/
find ${DOCPATH_STATIC}/ -type d -exec chmod 755 {} \;
find ${DOCPATH_STATIC}/ -type f -exec chmod 644 {} \;
find ${DOCPATH_STATIC}/ -name .htaccess -exec chmod 644 {} \;
find ${DOCPATH_STATIC}/ -name index.html -exec chmod 644 {} \;
find ${DOCPATH_STATIC}/ -name \*.sh -exec chmod 755 {} \;

chown -R ${USERNAME} ${APACHE_LOG}
chgrp -R ${USERNAME} ${APACHE_LOG}
find ${APACHE_LOG} -type d -exec chmod 755 {} \;
find ${APACHE_LOG} -type f -exec chmod 644 {} \;

# [Apache] User to APACHE_USER
chown -R ${APACHE_USER} ${APACHE_LOG}

# [Apache] Configure core
if [ -f ${CONFIG_OS_APACHE} ] && [ ! -f ${CONFIG_OS_APACHE}.bak ]; then
    # Backup original
    cp -f ${CONFIG_OS_APACHE} ${CONFIG_OS_APACHE}.bak
fi
cat <<EOF >${CONFIG_OS_APACHE}
DefaultRuntimeDir \${APACHE_RUN_DIR}
PidFile \${APACHE_PID_FILE}
Timeout 300
KeepAlive On
MaxKeepAliveRequests 100
KeepAliveTimeout 5

# These need to be set in /etc/apache2/envvars
User \${APACHE_RUN_USER}
Group \${APACHE_RUN_GROUP}

HostnameLookups Off

IncludeOptional mods-enabled/*.load
IncludeOptional mods-enabled/*.conf

Include ports.conf

<Directory />
        Options FollowSymLinks
        AllowOverride None
        Require all denied
</Directory>

AccessFileName .htaccess
<FilesMatch "^\.ht">
        Require all denied
</FilesMatch>

ErrorLog ${APACHE_LOG_DIR}/error.log
LogLevel warn
LogFormat "%v:%p %h %l %u %t \"%r\" %>s %O \"%{Referer}i\" \"%{User-Agent}i\"" vhost_combined
LogFormat "%v:%p %h %l %u %t \"%r\" %>s %O \"%{Referer}i\" \"%{User-Agent}i\"" vhost_combined
LogFormat "%h %l %u %t \"%r\" %>s %O \"%{Referer}i\" \"%{User-Agent}i\"" combined
LogFormat "%h %l %u %t \"%r\" %>s %O" common
LogFormat "%{Referer}i -> %U" referer
LogFormat "%{User-agent}i" agent

IncludeOptional conf-enabled/*.conf
IncludeOptional sites-enabled/*.conf
EOF

# [Apache] Configure http
# Note: certbot passes this path
cat <<EOF >${CONFIG_APACHE_DEFAULT}
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
a2ensite 000-default

# [Apache] Configure user
cat <<EOF >${CONFIG_APACHE_USER}
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
a2ensite ${USERNAME}

#endregion

#region Nginx

# [Nginx] User to APACHE_USER
chown -R ${APACHE_USER} ${NGINX_LOG}

# [Nginx] Configure core config
if [ -f ${CONFIG_OS_NGINX} ] && [ ! -f ${CONFIG_OS_NGINX}.bak ]; then
    # Backup original
    cp -f ${CONFIG_OS_NGINX} ${CONFIG_OS_NGINX}.bak
fi
cat <<EOF >${CONFIG_OS_NGINX}
user ${APACHE_USER};
worker_processes auto;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
        worker_connections 768;
        # multi_accept on;
}

http {
        sendfile on;
        tcp_nopush on;
        tcp_nodelay on;
        keepalive_timeout 65;
        types_hash_max_size 2048;
        # server_tokens off;

        # server_names_hash_bucket_size 64;
        # server_name_in_redirect off;

        include /etc/nginx/mime.types;
        default_type application/octet-stream;

        ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3; # Dropping SSLv3, ref: POODLE
        ssl_prefer_server_ciphers on;

        access_log ${NGINX_LOG}/access.log;
        error_log ${NGINX_LOG}/error.log;

        gzip on;

        include /etc/nginx/conf.d/*.conf;
        include /etc/nginx/sites-enabled/*;
}
EOF

# [Nginx] Configure http 80 as backup
cat <<EOF >${CONFIG_NGINX_DEFAULT}
server {
    listen 80 default_server;
    server_name _;

    root ${DOCPATH_HTTP};
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
rm -f /etc/nginx/sites-enabled/default

# [Nginx] Configure https 443
# Note: [] is not needed in if. Format is 'if "${boolean}"''
if "${NGINX_DEFAULT}"; then
    NGINX_LISTEN='listen 443 ssl default_server;'
else
    NGINX_LISTEN='listen 443 ssl;'
fi

NGINX_CONTENT=
if "${ENABLE_STATIC}"; then
    NGINX_CONTENT=$(
        cat <<EOF
    location ${LOCATION_STATIC}/ {
        alias ${DOCPATH_STATIC}/;
        autoindex on;
        index index.html;
    }
EOF
    )
fi

NGINX_VSCODE=
if "${ENABLE_VSCODE}"; then
    NGINX_VSCODE=$(
        cat <<EOF
    location ${LOCATION_VSCODE}/ {
        proxy_pass http://127.0.0.1:${CODESERVER_PORT}/;
        proxy_set_header Host \$host;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection upgrade;
        proxy_set_header Accept-Encoding gzip;
    }
EOF
    )
fi

cat <<EOF >${CONFIG_NGINX_USER}
server {
    ${NGINX_LISTEN}
    server_name ${USERNAME}.*;

    ssl_certificate ${NGINX_CERT_PATH}/fullchain.pem;
    ssl_certificate_key ${NGINX_CERT_PATH}/privkey.pem;

    ${NGINX_CONTENT}

    ${NGINX_VSCODE}

    location / {
        proxy_pass http://127.0.0.1:${APACHE_PORT}/;
        proxy_set_header Host \$host;
        proxy_set_header Accept-Encoding gzip;
    }
}
EOF
rm -f /etc/nginx/sites-enabled/${USERNAME}
ln -s ${CONFIG_NGINX_USER} /etc/nginx/sites-enabled/${USERNAME}

#endregion

#region logrotate

# [logrotate] Config
cat <<EOF >${CONFIG_OS_LOGROTATION}
weekly
rotate 10
create
missingok
include ${PATH_LOGROTATION_CONFIG}
EOF

# [logrotate] apache2
cat <<EOF >${CONFIG_LOGROTATION_APACHE}
${APACHE_LOG}/*.log {
    compress
    delaycompress
    notifempty
    create 0640 ${APACHE_USER} root
    sharedscripts
    postrotate
            if invoke-rc.d apache2 status > /dev/null 2>&1; then \
                invoke-rc.d apache2 reload > /dev/null 2>&1; \
            fi;
    endscript
    prerotate
            if [ -d ${PATH_LOGROTATION_CONFIG}/httpd-prerotate ]; then \
                    run-parts ${PATH_LOGROTATION_CONFIG}/httpd-prerotate; \
            fi; \
    endscript
}
EOF

# [logrotate] mysql-server
cat <<EOF >${CONFIG_LOGROTATION_MYSQL}
/var/log/mysql.log ${MYSQL_LOG}/*log {
    create 640 ${MYSQL_USER} ${MYSQL_USER}
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
cat <<EOF >${CONFIG_LOGROTATION_NGINX}
${NGINX_LOG}/*.log {
    compress
    delaycompress
    create 0640 ${APACHE_USER} root
    sharedscripts
    prerotate
            if [ -d ${PATH_LOGROTATION_CONFIG}/httpd-prerotate ]; then \
                run-parts ${PATH_LOGROTATION_CONFIG}/httpd-prerotate; \
            fi \
    endscript
    postrotate
            invoke-rc.d nginx rotate >/dev/null 2>&1
    endscript
}
EOF

# [logwatch] Config
cat <<EOF >${CONFIG_LOGWATCH}
TmpDir = ${DIR_DATA_LOGWATCH}
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

#endregion

#region Startup

# Add auto-start user instance
loginctl enable-linger ${USERNAME}

# Add auto-start and start services
# systemctl reload mysql
# systemctl reload apache2
# systemctl reload nginx

systemctl enable --now code-server@${USERNAME}
systemctl enable --now mysql
systemctl enable --now apache2
systemctl enable --now nginx

# [Cron] Schedule to pull
cat <<EOF >$0.crontab.conf
# Pull the latest for apache/php
*/5 * * * * /bin/sh -c 'cd ${DOCPATH_ROOT} && /usr/bin/git fetch --all && /usr/bin/git pull origin master'
# Pull the latest for static
*/5 * * * * /bin/sh -c 'cd ${DOCPATH_STATIC} && /usr/bin/git fetch --all && /usr/bin/git checkout . && /usr/bin/git clean -df && /usr/bin/git reset --hard origin/master && /usr/bin/git pull origin master'
EOF
crontab -u ${USERNAME} $0.crontab.conf

#endregion

#region Manual setup

cat <<EOF

TIPS

[MySQL] Remove root password
  1. Enable "skip-grant-tables" in /etc/mysql/conf.d/my.cnf
  2. sudo systemctl restart mysql
  3. Reset
    mysql -u root
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
  2. Confirm if /etc/ssh/sshd_config allows cert auth
    PubkeyAuthentication        yes
    AuthorizedKeysFile          .ssh/authorized_keys
  3. sudo systemctl restart sshd
  4. Confirm if ssh works with cert
  5. Confirm if /etc/ssh/sshd_config doesn't allow password auth
    PasswordAuthentication      no
  6. sudo systemctl restart sshd
EOF

#endregion
