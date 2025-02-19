#!/bin/bash

#region Variables

DIR_SELF=$(
    cd $(dirname $0)
    pwd
)

CONF=$1
if [ -z "${CONF}" ]; then
    # Load from default if no input
    CONF=$0.conf
fi

if [ ! -e ${CONF} ]; then
    echo "Usage: sudo ./setup.sh [conf=setup.sh.conf]"
    echo "Run \"touch ./setup.sh.conf\" for first run. This is needed action to avoid accidental run."
    exit 1
fi

source ${CONF}
source $0.default.conf

# USERNAME
USERNAME=$SUDO_USER
if [ -z "${USERNAME}" ]; then
    echo "Can't get User Name"
    exit 1
fi

# Trim a trailing slash from path
DOCPATH_HTTP=${DOCPATH_HTTP%/}
DOCPATH_HTTPS=${DOCPATH_HTTPS%/}
PATH_VSCODE=${PATH_VSCODE%/}
PATH_PHPMYADMIN=${PATH_PHPMYADMIN%/}
MACKEREL_PATH_APACHE=${MACKEREL_PATH_APACHE%/}
MACKEREL_PATH_NGINX=${MACKEREL_PATH_NGINX%/}

# OS_ARCH
ARCH=$(arch)
case $ARCH in
aarch64) OS_ARCH=arm64 ;;
*) OS_ARCH=amd64 ;;
esac

# PHP_VERS
PHP_VERS=(
    8.2
    8.1
    7.4
    7.3
    5.6
)

# NGINX_CERTPATH to self signed cert
if [ -z "${NGINX_CERTPATH}" ]; then
    NGINX_CERTPATH=${DIR_SELF}/cert
fi
NGINX_CERTPATH=${NGINX_CERTPATH%/}

# NGINX_FQDNS
NGINX_FQDNS=$(printf " %s" "${NGINX_FQDN[@]}")

# CERTBOT_COMMAND
CERTBOT_FQDNS=$(printf " -d %s" "${NGINX_FQDN[@]}")
CERTBOT_COMMAND="certbot certonly --agree-tos --webroot -w ${DOCPATH_HTTP} ${CERTBOT_FQDNS}"

# LOGWATCH_FROM
LOGWATCH_FROM=${SSMTP_AUTHUSER}
if [ -z "${LOGWATCH_FROM}" ]; then
    LOGWATCH_FROM=${USERNAME}@$(hostname)
fi

# LOGWATCH_TO
if [ -z "${LOGWATCH_TO}" ]; then
    if [ -n "${SSMTP_ROOTUSER}" ] && [ -n "${SSMTP_ROOTDOMAIN}" ]; then
        LOGWATCH_TO=${SSMTP_ROOTUSER}@${SSMTP_ROOTDOMAIN}
    else
        LOGWATCH_TO=${USERNAME}@$(hostname)
    fi
fi

# Configuration/Data path
DIR_CODESERVER_CONFIG=/home/${USERNAME}/.config/code-server
DIR_CODESERVER_DATA=/home/${USERNAME}/.local/share/code-server

CONFIG_LOGROTATION_APACHE=${DIR_LOGROTATION_CONFIG}/apache2
CONFIG_LOGROTATION_LIGHTTPD=${DIR_LOGROTATION_CONFIG}/lighttpd
CONFIG_LOGROTATION_MYSQL=${DIR_LOGROTATION_CONFIG}/mysql-server
CONFIG_LOGROTATION_MYSQLDUMP=${DIR_LOGROTATION_CONFIG}/mysqldump
CONFIG_LOGROTATION_NGINX=${DIR_LOGROTATION_CONFIG}/nginx

CONFIG_CODESERVER_INSTALLER=code-server_${CODESERVER_VER}_${OS_ARCH}.deb
CONFIG_CODESERVER=${DIR_CODESERVER_CONFIG}/config.yaml

CONFIG_VSCODE=${DIR_CODESERVER_DATA}/User/settings.json

CONFIG_NGINX_DEFAULT=/etc/nginx/sites-available/default
CONFIG_NGINX_USER=/etc/nginx/sites-available/${USERNAME}
CONFIG_APACHE_DEFAULT=/etc/apache2/sites-available/000-default.conf
CONFIG_APACHE_USER=/etc/apache2/sites-available/${USERNAME}.conf
CONFIG_APACHE_HTACCESS=${DOCPATH_HTTP}/.htaccess

CONFIG_MACKEREL_CONFIG=/etc/mackerel-agent/mackerel-agent.conf

# ssh
DIR_PUB=$(
    cd $(dirname $0)
    cd ../ssh-pubkey/
    pwd
)
DIR_PUBS=(
    ${DIR_PUB}/yubikey/
    ${DIR_PUB}/client/
)

SSH_AUTHKEYS=/home/${USERNAME}/.ssh/authorized_keys
SSH_AUTHKEYS_TMP=/home/${USERNAME}/.ssh/authorized_keys.tmp

if [ ! -e $(dirname ${SSH_AUTHKEYS_TMP}) ]; then
    sudo -u ${USERNAME} mkdir $(dirname ${SSH_AUTHKEYS_TMP})
fi
sudo -u ${USERNAME} echo -n >${SSH_AUTHKEYS_TMP}

for pubs in "${DIR_PUBS[@]}"; do
    if [ -e $pubs ]; then
        # {} represents the file being operated on during this iteration
        # \; closes the code statement and returns for next iteration
        find "$pubs" -name "*.pub" -type f -exec awk '1' $1 >>${SSH_AUTHKEYS_TMP} {} \;
    fi
done

if [ ! -s ${SSH_AUTHKEYS_TMP} ]; then
    echo "Can't get public certs"
    exit 1
fi
#endregion

#region Config confirmation
LIST_PORTS=$(printf "%s " "${ALLOWED_PORTS[@]}")
LIST_EXTS=$(printf "%s\n" "${CODESERVER_EXTS[@]}")
LIST_JOBS=$(printf "%s\n" "${CRON_JOBS[@]}")

cat <<EOF
[Service]
+-- Apache by Default
|   +-- Config: ${CONFIG_APACHE_DEFAULT}
|   +-- Domain: *
|   |
|   +-- /:80 (Fixed)
|   |   +-- Doc Path: ${DOCPATH_HTTP}
|   |   +-- htaccess: ${CONFIG_APACHE_HTACCESS}
|   |   +-- Redirect : ${NGINX_FQDN[0]}
|   |
|   +-- ${MACKEREL_PATH_APACHE}:${MACKEREL_PORT_APACHE}
|
+-- Nginx by Default
|   +-- Config: ${CONFIG_NGINX_DEFAULT}
|   +-- Domain: *
|   +-- SSL: ${NGINX_DEFAULT_CERTPATH}
|   |
|   +-- /:443 (Fixed)
|   |   +-- Doc Path: ${DOCPATH_HTTP}
|   |
|   +-- ${MACKEREL_PATH_NGINX}:${MACKEREL_PORT_NGINX}
|
+-- Nginx by User
|   +-- Config: ${CONFIG_NGINX_USER}
|   +-- Domain: ${NGINX_FQDNS}
|   +-- SSL: ${NGINX_CERTPATH}
|   |
|   +-- /:443 (Fixed) -> Apache:${PORT_HTTPS}
|   |   +-- Config: ${CONFIG_APACHE_USER}
|   |   +-- Doc Path: ${DOCPATH_HTTPS}
|   |
|   +-- ${PATH_VSCODE}:443 -> Code-Server:${PORT_VSCODE}
|   |   +-- Visible: ${ENABLE_VSCODE}
|   |   +-- Data Path: ${DIR_CODESERVER_DATA}
|   |   +-- Config: ${CONFIG_VSCODE}
|   |   +-- Installer: ${CONFIG_CODESERVER_INSTALLER}
|   |   +-- Password: ${CODESERVER_PASS}
|   |
|   +-- ${PATH_PHPMYADMIN}:443 -> Lighttpd:8888
|       +-- Visible: ${ENABLE_PHPMYADMIN}
|       +-- Lighttpd Config: ${CONFIG_OS_LIGHTTPD}
|
+-- Others
    +-- Allowed Ports: ${LIST_PORTS}

[User]
Unix: ${USERNAME}
Apache: ${APACHE_USER}
Lighttpd: ${APACHE_USER}
MySQL: ${MYSQL_USER}
Nginx: ${APACHE_USER}

[Config]
Apache: ${CONFIG_OS_APACHE}
Code-Server: ${CONFIG_CODESERVER}
Lighttpd: ${CONFIG_OS_LIGHTTPD}
Nginx: ${CONFIG_OS_NGINX}
MySQL: ${CONFIG_OS_MYSQL}
PHP: ${PHP_VER}

[Log Directories]
Group: ${LOG_GROUP}
Apache: ${DIR_APACHE_LOG}
Lighttpd: ${DIR_LIGHTTPD_LOG}
MySQL: ${DIR_MYSQL_LOG}
MySQLDump: ${DIR_MYSQLDUMP_LOG}
Nginx: ${DIR_NGINX_LOG}

[LogRotate]
Base: ${CONFIG_OS_LOGROTATION}
Apache: ${CONFIG_LOGROTATION_APACHE}
Lighttpd: ${CONFIG_LOGROTATION_LIGHTTPD}
MySQL: ${CONFIG_LOGROTATION_MYSQL}
MySQLDump: ${CONFIG_LOGROTATION_MYSQLDUMP}
Nginx: ${CONFIG_LOGROTATION_NGINX}

[LogWatch]
LogWatch: ${CONFIG_OS_LOGWATCH}
From: ${LOGWATCH_FROM}
To: ${LOGWATCH_TO}

[SSMTP]
SMTP Host: ${SSMTP_HOST}:${SSMTP_PORT}
SMTP TLS: ${SSMTP_TLS}
SMTP STARTTLS: ${SSMTP_STARTTLS}
SMTP User: ${SSMTP_AUTHUSER}
SMTP Pass: ${SSMTP_AUTHPASS}
Root Orverride: ${SSMTP_ROOTUSER}@${SSMTP_ROOTDOMAIN}

[VS Code Extensions]
${LIST_EXTS}

[Cron Jobs]
${LIST_JOBS}

[Certbot Command]
${CERTBOT_COMMAND}

[Public Certs]
EOF
cat ${SSH_AUTHKEYS_TMP}

if "${UPGRADE}"; then
    read -p "Hit enter to setup with upgrade: "
else
    read -p "Hit enter to setup: "
fi

#endregion

#region Base Setup

# [Base Setup] Skip password when sudo. The format is "${USERNAME} ALL=(ALL) NOPASSWD: ALL"
if ! grep -q ${USERNAME} /etc/sudoers; then
    echo ${USERNAME} ALL=\(ALL\) NOPASSWD: ALL >>/etc/sudoers
fi

# [Base Setup] Required directories
sudo -u ${USERNAME} mkdir -p ${DIR_SELF}/download
sudo -u ${USERNAME} mkdir -p ${DIR_CODESERVER_CONFIG}
sudo -u ${USERNAME} mkdir -p ${DIR_CODESERVER_DATA}

mkdir -p ${DIR_APACHE_LOG}
mkdir -p ${DIR_LIGHTTPD_LOG}
mkdir -p ${DIR_MYSQL_LOG}
mkdir -p ${DIR_MYSQLDUMP_LOG}
mkdir -p ${DIR_NGINX_LOG}

mkdir -p ${DIR_LOGROTATION_CONFIG}
mkdir -p ${DIR_LOGWATCH_DATA}
rm -rf ${DIR_LOGWATCH_DATA}/*

# [Base Setup] Reset user primary/secondary group
usermod -g ${USERNAME} ${USERNAME}
usermod -a -G ${APACHE_USER} ${USERNAME}
usermod -a -G ${LOG_GROUP} ${USERNAME}

# [Base Setup] Trigger backup before installing package
if [ -e ${CONFIG_OS_LOGROTATION} ] && "${UPGRADE}"; then
    logrotate -f ${CONFIG_OS_LOGROTATION}
fi

# [Base Setup] Install packages
add-apt-repository ppa:ondrej/php -y
apt-get -y update

if "${UPGRADE}"; then
    apt-get -y upgrade
fi

apt-get -y install ufw wget zip unzip jq moreutils ssmtp
apt-get -y install certbot python3 python3-pip python-is-python3
apt-get -y install ca-certificates apt-transport-https software-properties-common lsb-release
apt-get -y install nginx apache2 composer
apt-get -y install phpmyadmin lighttpd
apt-get -y install logrotate logwatch
apt-get -y install mackerel-agent-plugins mackerel-check-plugins

for phpver in "${PHP_VERS[@]}"; do
    apt-get -y install php$phpver libapache2-mod-php$phpver php$phpver-{apcu,cli,common,curl,fpm,gd,intl,mbstring,mysql,mysqli,soap,xml,zip}
done

apt-get -y autoremove

update-alternatives --list php
update-alternatives --set php /usr/bin/php${PHP_VER}

# [Base Setup] Firewall
ufw disable
ufw --force reset
ufw default deny

ufw allow 443
ufw allow 80
ufw allow 22
ufw allow ${MACKEREL_PORT_APACHE}
ufw allow ${MACKEREL_PORT_NGINX}
for port in "${ALLOWED_PORTS[@]}"; do
    ufw allow $port
done

# Not more than 6 times in 30 secs
ufw limit 22
ufw limit ${MACKEREL_PORT_APACHE}
ufw limit ${MACKEREL_PORT_NGINX}

# explicitly deny behide nginx
ufw deny ${PORT_HTTPS}
ufw deny ${PORT_VSCODE}
ufw deny 8888

ufw allow out 25
ufw allow out 587
ufw --force enable

#[Base Setup] ssh
mv -f ${SSH_AUTHKEYS_TMP} ${SSH_AUTHKEYS}

#endregion

#region Code-Server

# [Code-Server] Install
if [ ! -e ${DIR_SELF}/download/${CONFIG_CODESERVER_INSTALLER} ]; then
    sudo -u ${USERNAME} curl -fL https://github.com/coder/code-server/releases/download/v${CODESERVER_VER}/${CONFIG_CODESERVER_INSTALLER} -o ${DIR_SELF}/download/${CONFIG_CODESERVER_INSTALLER}
    dpkg -i ${DIR_SELF}/download/${CONFIG_CODESERVER_INSTALLER}
fi

# [Code-Server] Reset Permission
chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.local/
find ${DIR_CODESERVER_DATA} -type d -exec chmod 755 {} \;
find ${DIR_CODESERVER_DATA} -type f -exec chmod 644 {} \;

chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.config/
find ${DIR_CODESERVER_CONFIG} -type d -exec chmod 755 {} \;
find ${DIR_CODESERVER_CONFIG} -type f -exec chmod 644 {} \;

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

ExecStart=/usr/bin/code-server --host 127.0.0.1 --user-data-dir ${DIR_CODESERVER_DATA}
ExecStop=/bin/kill -s QUIT $MAINPID

[Install]
WantedBy=multi-user.target
EOF

# [Code-Server] User Config
cat <<EOF >${CONFIG_CODESERVER}
bind-addr: 127.0.0.1:${PORT_VSCODE}
auth: password
password: ${CODESERVER_PASS}
cert: false
user-data-dir: ${DIR_CODESERVER_DATA}
log: debug
EOF

# [Code-Server] Extensions
echo "Installed extensions:${INSTALLED[@]}"

installed() {
    for installed in "${INSTALLED[@]}"; do
        if [[ $installed = ${1} ]]; then
            # true
            return 0
        fi
    done
    # false
    return 1
}

# Manually install extensions that can't install from code-server marketplace
# Save installing extensions in vsix folder
INSTALLED=($(sudo -u ${USERNAME} code-server --list-extensions))
for vsix in ${DIR_SELF}/vsix/*.vsix; do
    extname=$(basename "$vsix" | sed -E 's/(.+)-[0-9.]+\.vsix/\1/')
    echo $vsix' -> '$extname
    if installed $extname; then
        echo "Already manually installed $extname"
    else
        sudo -u ${USERNAME} code-server --install-extension $vsix
    fi
done

# Install from marketplace
INSTALLED=($(sudo -u ${USERNAME} code-server --list-extensions))
for extension in "${CODESERVER_EXTS[@]}"; do
    if installed $extension; then
        echo "Already installed $extension"
    else
        sudo -u ${USERNAME} code-server --install-extension $extension
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

jq '."[jsonc]"."editor.defaultFormatter"|="esbenp.prettier-vscode"' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"

jq '."[markdown]"."editor.defaultFormatter"|="yzhang.markdown-all-in-one"' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '."[markdown]"."editor.wordWrap"|="off"' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"

jq '."[php]"."editor.defaultFormatter"|="junstyle.php-cs-fixer"' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '."[php]"."explicitFolding.rules"|=[]' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '."[php]"."explicitFolding.rules"+=[{"beginRegex":"(?:case|default)[^:]*:", "endRegex":"break;|(.)(?=case|default|\\})","foldLastLine":[true,false]}]' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '."[php]"."explicitFolding.rules"+=[{"beginRegex":"\\{", "middleRegex":"\\}[^}]+\\{", "endRegex":"\\}"}]' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"

jq '."[shellscript]"."explicitFolding.rules"|=[]' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '."[shellscript]"."explicitFolding.rules"+=[{"beginRegex":"#region", "endRegex":"#endregion", "autoFold":true}]' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '."[shellscript]"."explicitFolding.rules"+=[{"beginRegex":"\\{", "middleRegex":"\\}[^}]+\\{", "endRegex":"\\}"}]' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"

jq '.["breadcrumbs.enabled"]|=true' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"

jq '.["editor.defaultFoldingRangeProvider"]|="zokugun.explicit-folding"' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '.["editor.foldingStrategy"]|="auto"' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '.["editor.formatOnPaste"]|=true' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '.["editor.formatOnType"]|=true' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '.["editor.minimap.enabled"]|=true' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '.["editor.renderControlCharacters"]|=true' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '.["editor.renderWhitespace"]|="all"' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '.["editor.wordWrap"]|="off"' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"

jq '.["explorer.confirmDelete"]|=false' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '.["explorer.confirmDragAndDrop"]|=false' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"

jq '.["extensions.ignoreRecommendations"]|=true' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"

jq '.["files.associations"]|={"setup.*.conf":"shellscript"}' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '.["files.autoSave"]|="afterDelay"' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"

jq '.["git.autofetch"]|=true' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '.["git.confirmSync"]|=false' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '.["git.enableSmartCommit"]|=true' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"

jq '.["markdown.extension.preview.autoShowPreviewToSide"]|=false' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '.["markdown.extension.toc.updateOnSave"]|=false' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"

jq '.["php-cs-fixer.autoFixByBracket"]|=true' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '.["php-cs-fixer.autoFixBySemicolon"]|=true' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '.["php-cs-fixer.executablePath"]|="'${PHP_CS_FIXER_PHAR}'"' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '.["php-cs-fixer.formatHtml"]|=true' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '.["php-cs-fixer.lastDownload"]|=0' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '.["php-cs-fixer.rules"]|=""' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"

jq '.["projectManager.git.baseFolders"]|=["~/"]' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"

jq '.["security.workspace.trust.untrustedFiles"]|="open"' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"

jq '.["vsicons.dontShowNewVersionMessage"]|=true' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"

if [ -d "/home/${USERNAME}/OneDrive/Notes" ]; then
    jq '.["vsnotes.defaultNotePath"]|="/home/'${USERNAME}'/OneDrive/Notes"' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
fi
jq '.["vsnotes.defaultNoteTitle"]|="{title}.{ext}"' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '.["vsnotes.taskGroupBy"]|="file"' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '.["vsnotes.taskIncludeCompleted"]|=false' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '.["vsnotes.taskPrefix"]|="override"' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '.["vsnotes.treeviewHideTags"]|=true' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"

jq '.["workbench.colorTheme"]|="Default Dark Modern"' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
# jq '.["workbench.editorAssociations"]|={"*.md":"vscode.markdown.preview.editor"}' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '.["workbench.iconTheme"]|="vscode-icons"' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '.["workbench.startupEditor"]|="newUntitledFile"' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"

jq --sort-keys '.' ${CONFIG_VSCODE} | sponge ${CONFIG_VSCODE}
chown ${USERNAME}:${USERNAME} ${CONFIG_VSCODE}

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
# https://zenn.dev/zoeponta/articles/090c68ba820a24
collation-server = utf8mb4_0900_as_ci

# Timezone
default-time-zone = SYSTEM
log_timestamps = SYSTEM

default-authentication-plugin = mysql_native_password

basedir   = /var/lib/mysql
datadir   = /var/lib/mysql-files
pid-file  = /var/run/mysqld/mysqld.pid
socket    = /var/run/mysqld/mysqld.sock
log-error = ${DIR_MYSQL_LOG}/error.log
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

read_buffer_size = 1024K
join_buffer_size = 512K
sort_buffer_size = 512K
read_rnd_buffer_size = 512K
# max_allowed_packet = 8M
max_allowed_packet = 512M

connect_timeout = 60
net_read_timeout = 60
net_write_timeout = 120
interactive_timeout = 28800
wait_timeout = 28800

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
chown -R ${MYSQL_USER}:${LOG_GROUP} ${DIR_MYSQL_LOG}
chown -R ${MYSQL_USER}:${LOG_GROUP} ${DIR_MYSQLDUMP_LOG}

chmod 750 /var/lib/mysql
chmod 750 /var/lib/mysql-files
chmod 750 ${DIR_MYSQL_LOG}
chmod 750 ${DIR_MYSQLDUMP_LOG}

usermod -d /var/lib/mysql/ ${MYSQL_USER}
mysqld --initialize-insecure --user=${MYSQL_USER}

# [MySQL] Resolve warning at start
dpkg-divert --local --rename --add /sbin/initctl
if [ ! -e /sbin/initctl ]; then
    ln -s /bin/true /sbin/initctl
fi

# [MySQL] Create first backup file to trigger logrotate
if [ ! -e ${DIR_MYSQLDUMP_LOG}/${MYSQL_BACKUP_DB}.sql.gz ]; then
    touch ${DIR_MYSQLDUMP_LOG}/${MYSQL_BACKUP_DB}.sql
    gzip ${DIR_MYSQLDUMP_LOG}/${MYSQL_BACKUP_DB}.sql
    chown -R ${MYSQL_USER}:${LOG_GROUP} ${DIR_MYSQLDUMP_LOG}/${MYSQL_BACKUP_DB}.sql.gz
fi

#endregion

#region PHP

# [Php] php.ini
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
    sed "s|max_execution_time = 30|max_execution_time = 90|g" ${CONFIG_OS_PHP} | sponge ${CONFIG_OS_PHP}
    sed "s|mmemory_limit = 128M|memory_limit = 256M|g" ${CONFIG_OS_PHP} | sponge ${CONFIG_OS_PHP}
    sed "s|post_max_size = 8M|post_max_size = 16M|g" ${CONFIG_OS_PHP} | sponge ${CONFIG_OS_PHP}
    sed "s|upload_max_filesize = 2M|upload_max_filesize = 8M|g" ${CONFIG_OS_PHP} | sponge ${CONFIG_OS_PHP}
    sed "s|;mbstring.language = Japanese|;mbstring.language = Japanese|g" ${CONFIG_OS_PHP} | sponge ${CONFIG_OS_PHP}
done

#endregion

#region Apache

a2dismod ssl
a2dismod proxy
a2dismod proxy_http
a2dismod proxy_wstunnel
for phpver in "${PHP_VERS[@]}"; do
    a2dismod php$phpver
done

a2enmod authz_groupfile
a2enmod headers
a2enmod rewrite
a2enmod php${PHP_VER}

a2dissite default-ssl

# [Apache] Default .htaccess
# Allow certbot path
cat <<EOF >${CONFIG_APACHE_HTACCESS}
RewriteEngine On
RewriteCond %{REQUEST_URI} !(^/\.well-known(.*)$)
RewriteCond %{REQUEST_URI} !(^/(.*)\.html$)
RewriteCond %{HTTPS} off
RewriteRule ^(.*) https://${NGINX_FQDN[0]}/$1 [R=301,L]
EOF

# [Apache] Reset Permission: User(6)/UserGroup(6)/Other(4)
# Ubuntu 22.04 the user dir has 750 permissions by default
chmod 755 /home/${USERNAME}/

# Unix User as Owner: Read/Write 6xx
# Apache User as Group member: Read x4x
# Other User: Read xx4
chown -R ${APACHE_USER}:${USERNAME} ${DOCPATH_HTTP}/
find ${DOCPATH_HTTP}/ -type d -exec chmod 755 {} \;
find ${DOCPATH_HTTP}/ -type f -not -name "*.sh" -exec chmod 644 {} \;
find ${DOCPATH_HTTP}/ -name "*.sh" -exec chmod 755 {} \;

chown -R ${APACHE_USER}:${USERNAME} ${DOCPATH_HTTPS}/
find ${DOCPATH_HTTPS}/ -type d -exec chmod 755 {} \;
find ${DOCPATH_HTTPS}/ -type f -not -name "*.sh" -exec chmod 644 {} \;
find ${DOCPATH_HTTPS}/ -name "*.sh" -exec chmod 755 {} \;

# Allow Log Group to write
chown -R ${APACHE_USER}:${LOG_GROUP} ${DIR_APACHE_LOG}
find ${DIR_APACHE_LOG} -type d -exec chmod 775 {} \;
find ${DIR_APACHE_LOG} -type f -exec chmod 664 {} \;

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

Listen 80
Listen ${MACKEREL_PORT_APACHE}

<Directory />
    Options FollowSymLinks
    AllowOverride None
    Require all denied
</Directory>

AccessFileName .htaccess
<FilesMatch "^\.ht">
    Require all denied
</FilesMatch>

LogLevel warn
LogFormat "%v:%p %h %l %u %t \"%r\" %>s %O \"%{Referer}i\" \"%{User-Agent}i\"" vhost_combined
LogFormat "%h %l %u %t \"%r\" %>s %O \"%{Referer}i\" \"%{User-Agent}i\"" combined
LogFormat "%h %l %u %t \"%r\" %>s %O" common
LogFormat "%{Referer}i -> %U" referer
LogFormat "%{User-agent}i" agent

ErrorLog ${DIR_APACHE_LOG}/error.log

IncludeOptional conf-enabled/*.conf
IncludeOptional sites-enabled/*.conf
EOF

# [Apache] Configure default
cat <<EOF >${CONFIG_APACHE_DEFAULT}
AcceptFilter http none
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    ServerName localhost:80

    LogLevel warn
    ErrorLog ${DIR_APACHE_LOG}/error.log
    CustomLog ${DIR_APACHE_LOG}/access.log combined

    DocumentRoot ${DOCPATH_HTTP}
    <Directory ${DOCPATH_HTTP}>
        Options All
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>

ExtendedStatus On
<VirtualHost *:${MACKEREL_PORT_APACHE}>
    <Location ${MACKEREL_PATH_APACHE}>
        SetHandler server-status
        Order deny,allow
        Deny from all
        Allow from localhost
    </Location>
</VirtualHost>
EOF
rm -f /etc/apache2/sites-enabled/000-default.conf
a2ensite 000-default

# [Apache] Configure user
cat <<EOF >${CONFIG_APACHE_USER}
AcceptFilter http none
Listen ${PORT_HTTPS}
<VirtualHost *:${PORT_HTTPS}>
    ServerAdmin webmaster@localhost
    ServerName localhost:${PORT_HTTPS}

    LogLevel warn
    ErrorLog ${DIR_APACHE_LOG}/error.log
    CustomLog ${DIR_APACHE_LOG}/access.log combined

    DocumentRoot ${DOCPATH_HTTPS}
    <Directory ${DOCPATH_HTTPS}>
        Options None
        AllowOverride All
        Require all granted
    </Directory>

    Alias /application/views ${DOCPATH_HTTPS}/application/views
    <Directory ${DOCPATH_HTTPS}/application/views>
        Options None
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF
rm -f /etc/apache2/sites-enabled/${USERNAME}.conf
a2ensite ${USERNAME}

#endregion

#region phpmyadmin on lighttpd
# Web server to reconfigure automatically: <-- lighttpd
# Configure database for phpmyadmin with dbconfig-common? <-- Yes
#   sudo dpkg-reconfigure phpmyadmin
# MySQL application password for phpmyadmin: <-- Press Enter

lighty-enable-mod fastcgi 
lighty-enable-mod fastcgi-php

ln -s /usr/share/phpmyadmin ${DOCPATH_PHPMYADMIN}

chown -R ${APACHE_USER}:${LOG_GROUP} ${DIR_LIGHTTPD_LOG}

cat <<EOF >${CONFIG_OS_LIGHTTPD}
server.modules = (
    "mod_rewrite",
    "mod_redirect",
    "mod_access",
    "mod_auth",
    "mod_cgi",
    "mod_ssi",
    "mod_alias",
    "mod_compress",
    "mod_fastcgi",
    "mod_accesslog",
    "mod_rewrite",
)
server.document-root        = " ${DOCPATH_PHPMYADMIN}"
server.upload-dirs          = ( "/var/cache/lighttpd/uploads" )
server.errorlog             = "${DIR_LIGHTTPD_LOG}/error.log"
server.pid-file             = "/var/run/lighttpd.pid"
server.username             = "${APACHE_USER}"
server.groupname            = "${APACHE_USER}"
server.port                 = 8888

# features
#https://redmine.lighttpd.net/projects/lighttpd/wiki/Server_feature-flagsDetails
server.feature-flags       += ("server.h2proto" => "enable")
server.feature-flags       += ("server.h2c"     => "enable")
server.feature-flags       += ("server.graceful-shutdown-timeout" => 5)
#server.feature-flags      += ("server.graceful-restart-bg" => "enable")

# strict parsing and normalization of URL for consistency and security
# https://redmine.lighttpd.net/projects/lighttpd/wiki/Server_http-parseoptsDetails
# (might need to explicitly set "url-path-2f-decode" = "disable"
#  if a specific application is encoding URLs inside url-path)
server.http-parseopts = (
  "header-strict"           => "enable",# default
  "host-strict"             => "enable",# default
  "host-normalize"          => "enable",# default
  "url-normalize-unreserved"=> "enable",# recommended highly
  "url-normalize-required"  => "enable",# recommended
  "url-ctrls-reject"        => "enable",# recommended
  "url-path-2f-decode"      => "enable",# recommended highly (unless breaks app)
  "url-path-dotseg-remove"  => "enable",# recommended highly (unless breaks app)
)

index-file.names            = ( "index.php", "index.html" )
url.access-deny             = ( "~", ".inc" )
static-file.exclude-extensions = ( ".php", ".pl", ".fcgi" )

# default listening port for IPv6 falls back to the IPv4 port
include_shell "/usr/share/lighttpd/use-ipv6.pl " + server.port
include_shell "/usr/share/lighttpd/create-mime.conf.pl"
include "/etc/lighttpd/conf-enabled/*.conf"

server.modules += (
        "mod_dirlisting",
        "mod_staticfile",
)


fastcgi.server = (
    ".php" => (
        "localhost" => (
            "socket" => "/var/run/php/php7.0-fpm.sock",
            "broken-scriptfilename" => "enable"
        )
    )
)
EOF

#endregion

#region Nginx

# [Nginx] User to APACHE_USER
chown -R ${APACHE_USER}:${LOG_GROUP} ${DIR_NGINX_LOG}

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
    client_max_body_size 16M;
    # server_tokens off;

    # server_names_hash_bucket_size 64;
    # server_name_in_redirect off;

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    ssl_protocols TLSv1 TLSv1.1 TLSv1.2 TLSv1.3; # Dropping SSLv3, ref: POODLE
    ssl_prefer_server_ciphers on;

    access_log ${DIR_NGINX_LOG}/access.log;
    error_log ${DIR_NGINX_LOG}/error.log;

    gzip on;

    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF

# [Nginx] Configure default config
cat <<EOF >${CONFIG_NGINX_DEFAULT}
server {
    listen 443 default_server;
    server_name _;

    ssl_certificate ${NGINX_DEFAULT_CERTPATH}/fullchain.pem;
    ssl_certificate_key ${NGINX_DEFAULT_CERTPATH}/privkey.pem;

    root ${DOCPATH_HTTP};
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
server {
    listen ${MACKEREL_PORT_NGINX};
    server_name _;

    location ${MACKEREL_PATH_NGINX} {
        stub_status;
    }
}
EOF
rm -f /etc/nginx/sites-enabled/default
ln -s ${CONFIG_NGINX_DEFAULT} /etc/nginx/sites-enabled/default

# [Nginx] Configure https 443
# Note: [] is not needed in if. Format is 'if "${boolean}"''
NGINX_VSCODE=
if "${ENABLE_VSCODE}"; then
    NGINX_VSCODE=$(
        cat <<EOF
location ${PATH_VSCODE}/ {
    proxy_pass http://127.0.0.1:${PORT_VSCODE}/;
    proxy_set_header Host \$host;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection upgrade;
    proxy_set_header Accept-Encoding gzip;
    proxy_connect_timeout 120;
    proxy_send_timeout 180;
    proxy_read_timeout 180;
}
EOF
    )
fi

cat <<EOF >${CONFIG_NGINX_USER}
server {
    listen 443 ssl;
    server_name ${NGINX_FQDNS};

    ssl_certificate ${NGINX_CERTPATH}/fullchain.pem;
    ssl_certificate_key ${NGINX_CERTPATH}/privkey.pem;

    ${NGINX_VSCODE}

    location / {
        proxy_pass http://127.0.0.1:${PORT_HTTPS}/;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$remote_addr;
    }
}
EOF
rm -f /etc/nginx/sites-enabled/${USERNAME}
ln -s ${CONFIG_NGINX_USER} /etc/nginx/sites-enabled/${USERNAME}

#endregion

#region logrotate

# [logrotate] Config
cat <<EOF >${CONFIG_OS_LOGROTATION}
su root ${LOG_GROUP} 
daily
rotate 21
create
missingok
include ${DIR_LOGROTATION_CONFIG}
EOF

# [logrotate] apache2
cat <<EOF >${CONFIG_LOGROTATION_APACHE}
${DIR_APACHE_LOG}/*.log {
    compress
    delaycompress
    ifempty
    missingok
    create 0640 ${APACHE_USER} ${LOG_GROUP} 
    sharedscripts
    postrotate
        /bin/systemctl reload apache2 > /dev/null 2>/dev/null || true
    endscript
}
EOF

# [logrotate] lighttpd
cat <<EOF >${CONFIG_LOGROTATION_LIGHTTPD}
${DIR_LIGHTTPD_LOG}/*.log {
    compress
    delaycompress
    ifempty
    missingok
    create 0640 ${APACHE_USER} ${LOG_GROUP} 
    sharedscripts
    postrotate
        /bin/systemctl reload apache2 > /dev/null 2>/dev/null || true
    endscript
}
EOF

# [logrotate] mysql-server
cat <<EOF >${CONFIG_LOGROTATION_MYSQL}
${DIR_MYSQL_LOG}/*.log {
    compress
    delaycompress
    ifempty
    missingok
    create 0640 ${MYSQL_USER} ${LOG_GROUP} 
    sharedscripts
    postrotate
        test -x /usr/bin/mysqladmin || exit 0
        MYADMIN="/usr/bin/mysqladmin --defaults-file=/etc/mysql/debian.cnf"
        if [ -z "\`\$MYADMIN ping 2>/dev/null\`" ]; then
            if killall -q -s0 -umysql mysqld; then
                exit 1
            fi
        else
            \$MYADMIN flush-logs
        fi
    endscript
}
EOF

# [logrotate] mysqldump
cat <<EOF >${CONFIG_LOGROTATION_MYSQLDUMP}
${DIR_MYSQLDUMP_LOG}/*.sql.gz {
    nocompress
    daily
    rotate 14
    size 0
    missingok
    create 0640 ${MYSQL_USER} ${LOG_GROUP} 
    postrotate
        test -x /usr/bin/mysqldump || exit 0
        MYSQLDUMPOPTION="--single-transaction --quick --disable-keys --extended-insert --column-statistics=0 --compatible=ansi --skip-triggers --skip-quote-names --default-character-set=utf8 --no-tablespaces --set-gtid-purged=OFF --compression-algorithms=zlib -n -t"
        /usr/bin/mysqldump $MYSQLDUMPOPTION -h localhost -u root ${MYSQL_BACKUP_DB} | gzip > ${DIR_MYSQLDUMP_LOG}/${MYSQL_BACKUP_DB}.sql.gz
    endscript
}
EOF

# [logrotate] nginx
cat <<EOF >${CONFIG_LOGROTATION_NGINX}
${DIR_NGINX_LOG}/*.log {
    compress
    delaycompress
    ifempty
    missingok
    create 0640 ${APACHE_USER} ${LOG_GROUP} 
    sharedscripts
    postrotate
        /bin/systemctl reload nginx > /dev/null 2>/dev/null || true
    endscript
}
EOF

#endregion

#region mackerel
# [mackerel] Config
cat <<EOF >${CONFIG_MACKEREL_CONFIG}
apikey = "${MACKEREL_APIKEY}"
# pidfile = "/var/run/mackerel-agent.pid"
# root = "/var/lib/mackerel-agent"
# verbose = false

[plugin.checks.disk-space]
command = ["check-disk", "--warning", "20", "--critical", "10", "--path", "/"]


[plugin.checks.procs-sshd]
command = ["check-procs", "--pattern", "sshd"]

[plugin.checks.procs-nginx]
command = ["check-procs", "--pattern", "nginx"]

[plugin.checks.procs-apache2]
command = ["check-procs", "--pattern", "apache2"]

[plugin.checks.procs-mysqld]
command = ["check-procs", "--pattern", "mysqld"]

[plugin.checks.procs-lighttpd]
command = ["check-procs", "--pattern", "lighttpd"]


[plugin.checks.user_ssh]
command = ["check-log", "--file", "/var/log/auth.log", "--pattern", "(sshd:session): session opened", "--return"]
prevent_alert_auto_close = true

[plugin.checks.user_add]
command = ["check-log", "--file", "/var/log/auth.log", "--pattern", "new user", "--return"]
prevent_alert_auto_close = true

[plugin.checks.user_password]
command = ["check-log", "--file", "/var/log/auth.log", "--pattern", "password changed", "--return"]
prevent_alert_auto_close = true


[plugin.checks.login_vscode]
command = ["check-log", "--file", "${DIR_NGINX_LOG}/access.log", "--pattern", "POST /vscode/login HTTP/1\\\\..\" 302"]

[plugin.checks.login_toolsmysql]
command = ["check-log", "--file", "${DIR_NGINX_LOG}/access.log", "--pattern", "GET /tools/mysql/ HTTP/1\\\\..\" 200"]

[plugin.checks.login_toolslog]
command = ["check-log", "--file", "${DIR_NGINX_LOG}/access.log", "--pattern", "GET /tools/log/ HTTP/1\\\\..\" 200"]


# Plugin for Linux
[plugin.metrics.linux]
command = "mackerel-plugin-linux"

# Plugin for Apache2 (mod_status)
[plugin.metrics.apache2]
command = "mackerel-plugin-apache2 -p ${MACKEREL_PORT_APACHE} -s ${MACKEREL_PATH_APACHE}?auto"

[plugin.metrics.accesslog-apache]
command = "mackerel-plugin-accesslog ${DIR_APACHE_LOG}/access.log"

# Plugin for Nginx (stub_status)
[plugin.metrics.nginx]
command = "mackerel-plugin-nginx -port ${MACKEREL_PORT_NGINX} -path ${MACKEREL_PATH_NGINX}"

[plugin.metrics.accesslog-nginx]
command = "mackerel-plugin-accesslog ${DIR_NGINX_LOG}/access.log"

# Plugin for MySQL
# By default, the plugin accesses MySQL on localhost by 'root' with no password.
[plugin.metrics.mysql]
command = "mackerel-plugin-mysql"

# Plugin for Squid
[plugin.metrics.squid]
command = "mackerel-plugin-squid -port=8080"
EOF
#endregion

#region logwatch
# [logwatch] ssmtp
cat <<EOF >${CONFIG_OS_SSMTP}
MailHub=${SSMTP_HOST}:${SSMTP_PORT}
AuthUser=${SSMTP_AUTHUSER}
AuthPass=${SSMTP_AUTHPASS}
AuthMethod=LOGIN
UseTLS=${SSMTP_TLS}
UseSTARTTLS=${SSMTP_STARTTLS}
# Forward root mail
root=${SSMTP_ROOTUSER}@${SSMTP_ROOTDOMAIN}
# Add when domain is missing
RewriteDomain=${SSMTP_ROOTDOMAIN}
# YES - Allow the user to specify their own From: address
# NO - Use the system generated From: address
FromLineOverride=YES
HostName=$(hostname)
EOF

# [logwatch] Config
cat <<EOF >${CONFIG_OS_LOGWATCH}
TmpDir = ${DIR_LOGWATCH_DATA}
Output = mail
Format = html
Encode = none
Range = yesterday
Detail = 0
# From /usr/share/logwatch/default.conf/services
Service = All
Service = "-cron"
Service = "-dovecot"
Service = "-dpkg"
Service = "-kernel"
Service = "-postfix"
Service = "-rsyslogd"
Service = "-sendmail"
Service = "-sshd"
MailFrom = ${LOGWATCH_FROM}
MailTo = ${LOGWATCH_TO}
mailer = "/usr/sbin/sendmail -t"
EOF

#endregion

#region Startup

# Add auto-start user instance
loginctl enable-linger ${USERNAME}

# Add auto-start and start services
systemctl disable --now code-server

if "${UPGRADE}"; then
    systemctl disable --now code-server@${USERNAME}
    systemctl disable --now mysql
    systemctl disable --now apache2
    systemctl disable --now nginx
    systemctl disable --now mackerel-agent
fi

systemctl enable --now code-server@${USERNAME}
systemctl enable --now mysql
systemctl enable --now apache2
systemctl enable --now nginx
systemctl enable --now mackerel-agent

systemctl restart --now mackerel-agent

# [Cron] Schedule to pull
printf "%s\n" "${CRON_JOBS[@]}" >$0.crontab.conf
crontab -u ${USERNAME} $0.crontab.conf

#endregion

#region Manual setup

cat <<EOF

[MySQL] Remove root password:
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

[MySQL] Add root password for Production:
  sudo mysql_secure_installation

[SSH] Cert auth instead of password:
  1. Add id_rsa.pub/id_ed25519.pub to /home/${USERNAME}/.ssh/authorized_keys
  2. Update /etc/ssh/sshd_config to allow cert auth
    PubkeyAuthentication    yes
    AuthorizedKeysFile      .ssh/authorized_keys
  3. sudo systemctl restart sshd
  4. Confirm if ssh works with cert
  5. Update /etc/ssh/sshd_config not to allow password auth
    PasswordAuthentication          no
    ChallengeResponseAuthentication no
    PermitEmptyPasswords            no
    PermitRootLogin                 no
  6. sudo systemctl restart sshd
EOF
#endregion
