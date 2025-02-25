#!/bin/bash

#region args

# Check sudo or not
USERNAME=$SUDO_USER
if [ -z "${USERNAME}" ]; then
    echo "Can't get User Name"
    exit 1
fi

# getopts support short options
# -c [conf path]    default is setup.sh.conf
# -r                enable service restart
# -u                enable apt update/upgrade
RESTART=false
UPGRADE=false
while getopts "ruc:" optKey; do
    # echo key:$optKey
    # echo value:${OPTARG}
    case "$optKey" in
    c)
        echo "-${optKey}:${OPTARG}"
        CONF=${OPTARG}
        ;;
    r)
        echo "-${optKey}:${OPTARG}"
        RESTART=true
        ;;
    u)
        echo "-${optKey}:${OPTARG}"
        UPGRADE=true
        ;;
    esac
done
shift $((OPTIND - 1))

#endregion

#region Constants / Pre-defined variables

DIR_SELF=$(
    cd $(dirname $0)
    pwd
)

# Load setting
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

# Trim a trailing slash from path
DOCPATH_HTTP=${DOCPATH_HTTP%/}
DOCPATH_HTTPS=${DOCPATH_HTTPS%/}
DOCPATH_TOOLS=${DOCPATH_TOOLS%/}
PATH_VSCODE=${PATH_VSCODE%/}
PATH_TOOLS=${PATH_TOOLS%/}
PATH_TOOLS_PHPMYADMIN=${PATH_TOOLS_PHPMYADMIN%/}
PATH_TOOLS_PIMPMYLOG=${PATH_TOOLS_PIMPMYLOG%/}
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

# FQDNS
NGINX_FQDNS=$(printf " %s" "${NGINX_FQDN[@]}")
CERTBOT_FQDNS=$(printf " -d %s" "${NGINX_FQDN[@]}")
OAUTH2PROXY_FQDNS=$(printf "\"%s\"," "${NGINX_FQDN[@]}")
OAUTH2PROXY_MAILDOMAINS=$(printf "\"%s\"," "${OAUTH2_MAILDOMAINS[@]}")

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
INSTALLER_CODESERVER=code-server_${CODESERVER_VER}_${OS_ARCH}.deb
INSTALLER_PIMPMYLOG=pimp-my-log_master.zip
INSTALLER_PHPMYADMIN=phpmyadmin_${PHPMYADMIN_VER}.zip

DIR_CODESERVER_CONFIG=/home/${USERNAME}/.config/code-server
DIR_CODESERVER_DATA=/home/${USERNAME}/.local/share/code-server
DIR_PHPMYADMIN=/usr/share/phpmyadmin
DIR_PHPMYADMIN4=/usr/share/phpmyadmin4
DIR_PIMPMYLOG=/usr/share/pimp-my-log

CONFIG_LOGROTATION_APACHE=${DIR_LOGROTATION_CONFIG}/apache2
CONFIG_LOGROTATION_MYSQL=${DIR_LOGROTATION_CONFIG}/mysql-server
CONFIG_LOGROTATION_MYSQLDUMP=${DIR_LOGROTATION_CONFIG}/mysqldump
CONFIG_LOGROTATION_NGINX=${DIR_LOGROTATION_CONFIG}/nginx

CONFIG_CODESERVER=${DIR_CODESERVER_CONFIG}/config.yaml
CONFIG_VSCODE=${DIR_CODESERVER_DATA}/User/settings.json

CONFIG_NGINX_DEFAULT=/etc/nginx/sites-available/default
CONFIG_NGINX_USER=/etc/nginx/sites-available/${USERNAME}
CONFIG_APACHE_DEFAULT=/etc/apache2/sites-available/000-default.conf
CONFIG_APACHE_USER=/etc/apache2/sites-available/${USERNAME}.conf
CONFIG_APACHE_HTACCESS=${DOCPATH_HTTP}/.htaccess
CONFIG_OAUTH2PROXY=/etc/oauth2-proxy.${USERNAME}.conf
CONFIG_OAUTH2PROXY_EMAILS=/etc/oauth2-proxy-emails.${USERNAME}.conf

SYSTEMD_CODESERVER=/etc/systemd/system/code-server@${USERNAME}.service
SYSTEMD_OAUTH2PROXY=/etc/systemd/system/oauth2-proxy@${USERNAME}.service

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
        find "${pubs}" -name "*.pub" -type f -exec awk '1' {} \; >>${SSH_AUTHKEYS_TMP}
    fi
done

if [ ! -s ${SSH_AUTHKEYS_TMP} ]; then
    echo "Can't get public certs"
    exit 1
fi
#endregion

#region Config confirmation
list_ports=$(printf "%s " "${ALLOWED_PORTS[@]}")
list_exts=$(printf "%s\n" "${CODESERVER_EXTS[@]}")
list_jobs=$(printf "%s\n" "${CRON_JOBS[@]}")

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
|   +-- /:8888 (Fixed)
|   |   +-- Visible: ${ENABLE_TOOLS}
|   |   +-- Doc Path: ${DOCPATH_TOOLS}
|   |   |
|   |   +-- ${PATH_TOOLS_PHPMYADMIN}: ${DIR_PHPMYADMIN}
|   |   |
|   |   +-- ${PATH_TOOLS_PIMPMYLOG}: ${DIR_PIMPMYLOG}
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
|   |   +-- Installer: ${INSTALLER_CODESERVER}
|   |   +-- Password: ${CODESERVER_PASS}
|   |
|   +-- ${PATH_TOOLS}:443 -> Apache:8888
|
+-- Others
    +-- Allowed Ports: ${list_ports}

[User]
Unix: ${USERNAME}
Apache: ${APACHE_USER}
MySQL: ${MYSQL_USER}
Nginx: ${APACHE_USER}

[Config]
Apache: ${CONFIG_OS_APACHE}
Code-Server: ${CONFIG_CODESERVER}
Nginx: ${CONFIG_OS_NGINX}
MySQL: ${CONFIG_OS_MYSQL}
PHP: ${PHP_VER}

[Log Directories]
Group: ${LOG_GROUP}
Apache: ${DIR_APACHE_LOG}
MySQL: ${DIR_MYSQL_LOG}
MySQLDump: ${DIR_MYSQLDUMP_LOG}
Nginx: ${DIR_NGINX_LOG}

[LogRotate]
Base: ${CONFIG_OS_LOGROTATION}
Apache: ${CONFIG_LOGROTATION_APACHE}
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
${list_exts}

[Cron Jobs]
${list_jobs}

[Certbot Command]
certbot certonly --agree-tos --webroot -w ${DOCPATH_HTTP} ${CERTBOT_FQDNS}

[API]
MACKEREL_APIKEY: ${MACKEREL_APIKEY}
OAUTH2_CLIENT: ${OAUTH2_CLIENT}
OAUTH2_SECRET: ${OAUTH2_SECRET}

[Public Certs]
EOF
cat ${SSH_AUTHKEYS_TMP}
read -p "Hit enter to setup ([apt:${UPGRADE}],[restart:${RESTART}]): "

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

# [Base Setup] Reset permission

# Ubuntu 22.04 the user dir has 750 permissions by default
chmod 755 /home/${USERNAME}/

# Unix User as Owner: Read/Write 6xx
# Apache User as Group member: Read x4x
# Other User: Read xx4
chown -R ${USERNAME}:${USERNAME} ${DOCPATH_HTTP}/
find ${DOCPATH_HTTP}/ -type d -exec chmod 755 {} \;
find ${DOCPATH_HTTP}/ -type f -not -name "*.sh" -exec chmod 644 {} \;
find ${DOCPATH_HTTP}/ -name "*.sh" -exec chmod 755 {} \;

chown -R ${USERNAME}:${USERNAME} ${DOCPATH_HTTPS}/
find ${DOCPATH_HTTPS}/ -type d -exec chmod 755 {} \;
find ${DOCPATH_HTTPS}/ -type f -not -name "*.sh" -exec chmod 644 {} \;
find ${DOCPATH_HTTPS}/ -name "*.sh" -exec chmod 755 {} \;

if [ ! -e ${DOCPATH_TOOLS} ]; then
    mkdir -p ${DOCPATH_TOOLS}
fi
if [ ! -e ${DOCPATH_TOOLS}/index.php ]; then
    touch -p ${DOCPATH_TOOLS}/index.php
fi
chown -R ${USERNAME}:${USERNAME} ${DOCPATH_TOOLS}/
find ${DOCPATH_TOOLS}/ -type d -exec chmod 755 {} \;
find ${DOCPATH_TOOLS}/ -type f -not -name "*.sh" -exec chmod 644 {} \;
find ${DOCPATH_TOOLS}/ -name "*.sh" -exec chmod 755 {} \;

# [Base Setup] Trigger backup before installing package
if [ -e ${CONFIG_OS_LOGROTATION} ] && "${RESTART}"; then
    logrotate -f ${CONFIG_OS_LOGROTATION}
fi

# [Base Setup] Install packages
add-apt-repository ppa:ondrej/php -y
add-apt-repository ppa:longsleep/golang-backports -y

if "${UPGRADE}"; then
    apt-get -y update
    apt-get -y upgrade
fi

apt-get -y install ufw wget zip unzip jq moreutils ssmtp
apt-get -y install certbot python3 python3-pip python-is-python3
apt-get -y install ca-certificates apt-transport-https software-properties-common lsb-release
apt-get -y install nginx apache2
apt-get -y install composer phpmyadmin
apt-get -y install logrotate logwatch
apt-get -y install mackerel-agent-plugins mackerel-check-plugins
apt-get -y install golang-go

for phpver in "${PHP_VERS[@]}"; do
    apt-get -y install php${phpver} libapache2-mod-php${phpver} php${phpver}-{apcu,cli,common,curl,fpm,gd,intl,mbstring,mysql,mysqli,soap,xml,zip}
done

apt-get -y autoremove

# update-alternatives --list php
update-alternatives --set php /usr/bin/php${PHP_VER}

# update-alternatives --list editor
update-alternatives --set editor /usr/bin/vim.basic

# [Base Setup] Firewall
ufw disable
#ufw --force reset
ufw default deny

ufw allow 443
ufw allow 80
ufw allow 22
for port in "${ALLOWED_PORTS[@]}"; do
    ufw allow ${port}
done

# Not more than 6 times in 30 secs
ufw limit 22

# explicitly deny behide nginx
ufw deny ${PORT_HTTPS}
ufw deny ${PORT_VSCODE}
ufw deny ${PORT_OAUTH2PROXY}
ufw deny 8888
ufw deny ${MACKEREL_PORT_APACHE}
ufw deny ${MACKEREL_PORT_NGINX}

ufw allow out 25
ufw allow out 587
ufw --force enable

#[Base Setup] ssh
mv -f ${SSH_AUTHKEYS_TMP} ${SSH_AUTHKEYS}

#endregion

#region Code-Server

# [Code-Server] Install
if [ ! -e ${DIR_SELF}/download/${INSTALLER_CODESERVER} ]; then
    sudo -u ${USERNAME} curl -fL https://github.com/coder/code-server/releases/download/v${CODESERVER_VER}/${INSTALLER_CODESERVER} -o ${DIR_SELF}/download/${INSTALLER_CODESERVER}
    dpkg -i ${DIR_SELF}/download/${INSTALLER_CODESERVER}
fi

# [Code-Server] Reset Permission
chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.local/
find ${DIR_CODESERVER_DATA} -type d -exec chmod 755 {} \;
find ${DIR_CODESERVER_DATA} -type f -exec chmod 644 {} \;

chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.config/
find ${DIR_CODESERVER_CONFIG} -type d -exec chmod 755 {} \;
find ${DIR_CODESERVER_CONFIG} -type f -exec chmod 644 {} \;

# [Code-Server] User Config
cat <<EOF >${CONFIG_CODESERVER}
bind-addr: 127.0.0.1:${PORT_VSCODE}
auth: password
password: ${CODESERVER_PASS}
cert: false
user-data-dir: ${DIR_CODESERVER_DATA}
log: debug
EOF

# [Code-Server] Startup
cat <<EOF >${SYSTEMD_CODESERVER}
[Unit]
Description=code-server
After=syslog.target network.target

[Service]
Type=simple
User=${USERNAME}
Group=${USERNAME}
WorkingDirectory=/home/${USERNAME}
Restart=always
RestartSec=10

ExecStart=/usr/bin/code-server --host 127.0.0.1 --user-data-dir ${DIR_CODESERVER_DATA}
ExecStop=/bin/kill -s QUIT $MAINPID

[Install]
WantedBy=multi-user.target
EOF

# [Code-Server] Extensions
echo "Installed extensions:${INSTALLED[@]}"

installed() {
    for installed in "${INSTALLED[@]}"; do
        if [[ ${installed} = ${1} ]]; then
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
    if installed ${extension}; then
        echo "Already installed ${extension}"
    else
        sudo -u ${USERNAME} code-server --install-extension ${extension}
    fi
done

# [Code-Server] Extension config
if [ ! -e ${CONFIG_VSCODE} ]; then
    sudo -u ${USERNAME} touch ${CONFIG_VSCODE}
fi
phar=${DIR_SELF}/download/php-cs-fixer.phar
if [ ! -e ${phar} ]; then
    sudo -u ${USERNAME} curl -fL https://cs.symfony.com/download/php-cs-fixer-v3.phar -o ${phar}
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
jq '.["php-cs-fixer.executablePath"]|="'${phar}'"' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '.["php-cs-fixer.formatHtml"]|=true' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '.["php-cs-fixer.lastDownload"]|=0' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"
jq '.["php-cs-fixer.rules"]|=""' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"

jq '.["projectManager.git.baseFolders"]|=["~/"]' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"

jq '.["security.workspace.trust.untrustedFiles"]|="open"' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"

jq '.["vsicons.dontShowNewVersionMessage"]|=true' "${CONFIG_VSCODE}" | sponge "${CONFIG_VSCODE}"

if [ -d -e "/home/${USERNAME}/OneDrive/Notes" ]; then
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

#region oauth2-proxy

# Run if oauth client and secret are available
if [ -n "${OAUTH2_CLIENT}" ] && [ -n "${OAUTH2_SECRET}" ]; then
    echo "Setting up oauth2-proxy..."

    export GOPATH=/home/${USERNAME}/.go
    if [ ! -e "/home/${USERNAME}/.go" ]; then
        sudo -u ${USERNAME} mkdir /home/${USERNAME}/.go
    fi

    # https://oauth2-proxy.github.io/oauth2-proxy/installation/
    go install github.com/oauth2-proxy/oauth2-proxy/v7@latest
    cookie_secret=$(openssl rand -base64 32 | tr -- '+/' '-_')

    # [OAuth2-Proxy] Allowed email
    sudo -u ${USERNAME} echo -n >${CONFIG_OAUTH2PROXY_EMAILS}
    if [ -n "${OAUTH2_MAILUSERS}" ]; then
        for email in "${OAUTH2_MAILUSERS[@]}"; do
            echo $email >>${CONFIG_OAUTH2PROXY_EMAILS}
        done
    fi

    # [OAuth2-Proxy] User Config
    # https://github.com/oauth2-proxy/oauth2-proxy/blob/master/contrib/local-environment/oauth2-proxy-nginx.cfg
    list_ports=$(printf "%s " "${ALLOWED_PORTS[@]}")
    cat <<EOF >${CONFIG_OAUTH2PROXY}
http_address="0.0.0.0:${PORT_OAUTH2PROXY}"
cookie_secret="${cookie_secret}"
provider="oidc"
email_domains=[${OAUTH2PROXY_MAILDOMAINS}]
#authenticated-emails-file="${CONFIG_OAUTH2PROXY_EMAILS}"

client_id="${OAUTH2_CLIENT}"
client_secret="${OAUTH2_SECRET}"

cookie_secure="true"
reverse_proxy="true"

oidc_issuer_url="https://accounts.google.com"
#redirect_url="https://azure.mafut.com/oauth2/callback"

# Required so cookie can be read on all subdomains.
cookie_domains=[${OAUTH2PROXY_FQDNS}]

# Required to allow redirection back to original requested target.
whitelist_domains=[${OAUTH2PROXY_FQDNS}]
EOF

    # [OAuth2-Proxy] Startup
    # https://github.com/oauth2-proxy/oauth2-proxy/blob/master/contrib/oauth2-proxy.service.example
    cat <<EOF >${SYSTEMD_OAUTH2PROXY}
[Unit]
Description=oauth2_proxy daemon service
After=syslog.target network.target

[Service]
User=${USERNAME}
Group=${USERNAME}
ExecStart=/home/${USERNAME}/.go/bin/oauth2-proxy --config=${CONFIG_OAUTH2PROXY} --authenticated-emails-file=${CONFIG_OAUTH2PROXY_EMAILS}
ExecReload=/bin/kill -HUP \$MAINPID
NoNewPrivileges=true
KillMode=process
Restart=always

[Install]
WantedBy=multi-user.target
EOF

fi

#endregion

#region pimp-my-log/phpmyadmin

# phpinfo
cat <<EOF >${DOCPATH_TOOLS}/index.php
<?php phpinfo(); ?>
EOF

# [pimp-my-log] Download
if [ ! -e ${DIR_SELF}/download/${INSTALLER_PIMPMYLOG} ]; then
    sudo -u ${USERNAME} curl -fL https://github.com/potsky/PimpMyLog/zipball/master -o ${DIR_SELF}/download/${INSTALLER_PIMPMYLOG}
fi
rm -rf ${DIR_PIMPMYLOG}
unzip -o -q -d ${DIR_SELF}/download/ ${DIR_SELF}/download/${INSTALLER_PIMPMYLOG}
mv -f ${DIR_SELF}/download/potsky-PimpMyLog-* ${DIR_PIMPMYLOG}

# [pimp-my-log] Modify csrf_verify
# PHPSESSID doesn't stay in cookie
sed "s|return ( .s === .*;|return true;|g" ${DIR_PIMPMYLOG}/inc/global.inc.php | sponge ${DIR_PIMPMYLOG}/inc/global.inc.php

# [pimp-my-log] Config
cat <<EOF >${DIR_PIMPMYLOG}/config.user.php
<?php if(realpath(__FILE__)===realpath(\$_SERVER["SCRIPT_FILENAME"])){header(\$_SERVER['SERVER_PROTOCOL'].' 404 Not Found');die();}?>
{
    "globals": {
        "_remove_me_to_set_AUTH_LOG_FILE_COUNT"         : 100,
        "_remove_me_to_set_AUTO_UPGRADE"                : false,
        "_remove_me_to_set_CHECK_UPGRADE"               : false,
        "_remove_me_to_set_EXPORT"                      : true,
        "_remove_me_to_set_FILE_SELECTOR"               : "bs",
        "_remove_me_to_set_GOOGLE_ANALYTICS"            : "UA-XXXXX-X",
        "_remove_me_to_set_LOCALE"                      : "en_US",
        "_remove_me_to_set_LOGS_MAX"                    : 50,
        "_remove_me_to_set_LOGS_REFRESH"                : 0,
        "_remove_me_to_set_MAX_SEARCH_LOG_TIME"         : 5,
        "_remove_me_to_set_NAV_TITLE"                   : "",
        "_remove_me_to_set_NOTIFICATION"                : true,
        "_remove_me_to_set_NOTIFICATION_TITLE"          : "New logs [%f]",
        "_remove_me_to_set_PULL_TO_REFRESH"             : true,
        "_remove_me_to_set_SORT_LOG_FILES"              : "default",
        "_remove_me_to_set_TAG_DISPLAY_LOG_FILES_COUNT" : true,
        "_remove_me_to_set_TAG_NOT_TAGGED_FILES_ON_TOP" : true,
        "_remove_me_to_set_TAG_SORT_TAG"                : "default | display-asc | display-insensitive | display-desc | display-insensitive-desc",
        "_remove_me_to_set_TITLE"                       : "Pimp my Log",
        "_remove_me_to_set_TITLE_FILE"                  : "Pimp my Log [%f]",
        "_remove_me_to_set_USER_CONFIGURATION_DIR"      : "config.user.d",
        "_remove_me_to_set_USER_TIME_ZONE"              : "PST8PDT"
    },

    "badges": {
        "severity": {
            "debug"       : "success",
            "info"        : "success",
            "notice"      : "default",
            "Notice"      : "info",
            "warn"        : "warning",
            "error"       : "danger",
            "crit"        : "danger",
            "alert"       : "danger",
            "emerg"       : "danger",
            "Notice"      : "info",
            "Fatal error" : "danger",
            "Parse error" : "danger",
            "Warning"     : "warning"
        },
        "http": {
            "1" : "info",
            "2" : "success",
            "3" : "default",
            "4" : "warning",
            "5" : "danger"
        }
    },

    "files": {
        "apache_access": {
            "display"   : "Apache Access",
            "path"      : "${DIR_APACHE_LOG//\//\\/}\/access.log",
            "refresh"   : 0,
            "max"       : 50,
            "notify"    : false,
            "multiline" : "",
            "format"    : {
                "regex"        : "|^(.*) (.*) (.*) \\\\[(.*)\\\\] \"(.*) (.*) (.*)\" ([0-9]*) (.*) \"(.*)\" \"(.*)\"( [0-9]*\/([0-9]*))*$|U",
                "export_title" : "URL",
                "match"        : {
                    "Date"    : 4,
                    "IP"      : 1,
                    "CMD"     : 5,
                    "URL"     : 6,
                    "Code"    : 8,
                    "Size"    : 9,
                    "Referer" : 10,
                    "UA"      : 11,
                    "User"    : 3,
                    "\u03bcs" : 13
                },
                "types": {
                    "Date"    : "date:H:i:s",
                    "IP"      : "ip:geo",
                    "URL"     : "txt",
                    "Code"    : "badge:http",
                    "Size"    : "numeral:0b",
                    "Referer" : "link",
                    "UA"      : "ua:{os.name} {os.version} | {browser.name} {browser.version}\/100",
                    "\u03bcs" : "numeral:0,0"
                },
                "exclude": {
                    "URL": ["\/favicon.ico\/", "\/\\\\.pml\\\\.php.*$\/", "${MACKEREL_PATH_APACHE//\//\\/}\/"],
                    "CMD": ["\/OPTIONS\/"]
                }
            }
        },
        "nginx_access": {
            "display"   : "Nginx Access",
            "path"      : "${DIR_NGINX_LOG//\//\\/}\/access.log",
            "refresh"   : 0,
            "max"       : 50,
            "notify"    : false,
            "multiline" : "",
            "format"    : {
                "regex"        : "|^(.*) (.*) (.*) \\\\[(.*)\\\\] \"(.*) (.*) (.*)\" ([0-9]*) (.*) \"(.*)\" \"(.*)\"( [0-9]*\/([0-9]*))*$|U",
                "export_title" : "URL",
                "match"        : {
                    "Date"    : 4,
                    "IP"      : 1,
                    "CMD"     : 5,
                    "URL"     : 6,
                    "Code"    : 8,
                    "Size"    : 9,
                    "Referer" : 10,
                    "UA"      : 11,
                    "User"    : 3,
                    "\u03bcs" : 13
                },
                "types": {
                    "Date"    : "date:H:i:s",
                    "IP"      : "ip:geo",
                    "URL"     : "txt",
                    "Code"    : "badge:http",
                    "Size"    : "numeral:0b",
                    "Referer" : "link",
                    "UA"      : "ua:{os.name} {os.version} | {browser.name} {browser.version}\/100",
                    "\u03bcs" : "numeral:0,0"
                },
                "exclude": {
                    "URL": ["\/favicon.ico\/", "\/\\\\.pml\\\\.php.*$\/", "${MACKEREL_PATH_NGINX//\//\\/}\/"],
                    "CMD": ["\/OPTIONS\/"]
                }
            }
        },
        "apache_error": {
            "display"   : "Apache Error",
            "path"      : "${DIR_APACHE_LOG//\//\\/}\/error.log",
            "refresh"   : 0,
            "max"       : 50,
            "notify"    : false,
            "multiline" : "",
            "format"    : {
                "regex"        : "|^\\\\[([^\\\\]]*)\\\\] \\\\[([^\\\\]]*)\\\\] (\\\\[pid ([^\\\\]]*)\\\\] )*(\\\\[client ([^\\\\]]*)\\\\] )*(\\\\[referer ([^\\\\]]*)\\\\] )*(.*)$|U",
                "export_title" : "Log",
                "match"        : {
                    "Date"     : 1,
                    "IP"       : 6,
                    "Log"      : 9,
                    "Severity" : 2,
                    "Referer"  : 8
                },
                "types": {
                    "Date"     : "date:H:i:s",
                    "IP"       : "ip:http",
                    "Log"      : "pre",
                    "Severity" : "badge:severity",
                    "Referer"  : "link"
                },
                "exclude": {
                    "Log": ["\/PHP Stack trace:\/", "\/PHP *[0-9]*\\\\. \/"]
                }
            }
        },
        "nginx_error": {
            "display"   : "Nginx Error",
            "path"      : "${DIR_NGINX_LOG//\//\\/}\/error.log",
            "refresh"   : 0,
            "max"       : 50,
            "notify"    : false,
            "multiline" : "",
            "format"    : {
                "regex"        : "|^\\\\[([^\\\\]]*)\\\\] \\\\[([^\\\\]]*)\\\\] (\\\\[pid ([^\\\\]]*)\\\\] )*(\\\\[client ([^\\\\]]*)\\\\] )*(\\\\[referer ([^\\\\]]*)\\\\] )*(.*)$|U",
                "export_title" : "Log",
                "match"        : {
                    "Date"     : 1,
                    "IP"       : 6,
                    "Log"      : 9,
                    "Severity" : 2,
                    "Referer"  : 8
                },
                "types": {
                    "Date"     : "date:H:i:s",
                    "IP"       : "ip:http",
                    "Log"      : "pre",
                    "Severity" : "badge:severity",
                    "Referer"  : "link"
                },
                "exclude": {
                    "Log": ["\/PHP Stack trace:\/", "\/PHP *[0-9]*\\\\. \/"]
                }
            }
        }
    }
}
EOF

# [phpmyadmin] Download old version for old php
if [ ! -e ${DIR_SELF}/download/${INSTALLER_PHPMYADMIN} ]; then
    sudo -u ${USERNAME} curl -fL https://files.phpmyadmin.net/phpMyAdmin/${PHPMYADMIN_VER}/phpMyAdmin-${PHPMYADMIN_VER}-all-languages.zip -o ${DIR_SELF}/download/${INSTALLER_PHPMYADMIN}
fi
rm -rf ${DIR_PHPMYADMIN4}
unzip -o -q -d ${DIR_SELF}/download/ ${DIR_SELF}/download/${INSTALLER_PHPMYADMIN}
mv -f ${DIR_SELF}/download/phpMyAdmin-${PHPMYADMIN_VER}-* ${DIR_PHPMYADMIN4}

# [pimp-my-log/phpmyadmin] Link
ln -fns ${DIR_PIMPMYLOG} ${DOCPATH_TOOLS}/${PATH_TOOLS_PIMPMYLOG}
ln -fns ${DIR_PHPMYADMIN4} ${DOCPATH_TOOLS}/${PATH_TOOLS_PHPMYADMIN}
#ln -fns ${DIR_PHPMYADMIN} ${DOCPATH_TOOLS}/${PATH_TOOLS_PHPMYADMIN}

#endregion

#region MySQL

# [MySQL] Config
if [ -f -e ${CONFIG_OS_MYSQL} ] && [ ! -e ${CONFIG_OS_MYSQL}.bak ]; then
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
for db in "${BACKUP_DB[@]}"; do
    if [ ! -e ${DIR_MYSQLDUMP_LOG}/${db}.sql.gz ]; then
        touch ${DIR_MYSQLDUMP_LOG}/${db}.sql
        gzip ${DIR_MYSQLDUMP_LOG}/${db}.sql
        chown -R ${MYSQL_USER}:${LOG_GROUP} ${DIR_MYSQLDUMP_LOG}/${db}.sql.gz
    fi
done
#endregion

#region PHP

# [Php] php.ini
for phpver in "${PHP_VERS[@]}"; do
    phpini=/etc/php/${phpver}/apache2/php.ini

    if [ -f -e ${phpini} ] && [ ! -e ${phpini}.bak ]; then
        # Backup original
        cp -f ${phpini} ${phpini}.bak
    fi
    sed "s|display_errors = Off|display_errors = On|g" ${phpini} | sponge ${phpini}
    sed "s|display_startup_errors = Off|display_startup_errors = On|g" ${phpini} | sponge ${phpini}
    sed "s|;extension_dir = "./"|extension_dir = "./"|g" ${phpini} | sponge ${phpini}
    sed "s|;extension=php_soap.dll|extension=php_soap.dll|g" ${phpini} | sponge ${phpini}
    sed "s|;extension=curl|extension=curl|g" ${phpini} | sponge ${phpini}
    sed "s|;extension=mysqli|extension=mysqli|g" ${phpini} | sponge ${phpini}
    sed "s|max_execution_time = 30|max_execution_time = 90|g" ${phpini} | sponge ${phpini}
    sed "s|mmemory_limit = 128M|memory_limit = 256M|g" ${phpini} | sponge ${phpini}
    sed "s|post_max_size = 8M|post_max_size = 16M|g" ${phpini} | sponge ${phpini}
    sed "s|upload_max_filesize = 2M|upload_max_filesize = 8M|g" ${phpini} | sponge ${phpini}
    sed "s|;mbstring.language = Japanese|;mbstring.language = Japanese|g" ${phpini} | sponge ${phpini}
    sed "s|session.cookie_samesite =$|session.cookie_samesite = Lax|g" ${phpini} | sponge ${phpini}
    sed "s|session.cookie_httponly =$|session.cookie_httponly = On|g" ${phpini} | sponge ${phpini}
    sed "s|session.cookie_lifetime = 0|session.cookie_lifetime = 7200|g" ${phpini} | sponge ${phpini}
done

#endregion

#region Apache

a2dismod ssl
a2dismod proxy
a2dismod proxy_http
a2dismod proxy_wstunnel
for phpver in "${PHP_VERS[@]}"; do
    a2dismod php${phpver}
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
RewriteCond %{REQUEST_URI} !(^${MACKEREL_PATH_APACHE}(.*)$)
RewriteCond %{REQUEST_URI} !(^/\.well-known(.*)$)
RewriteCond %{REQUEST_URI} !(^/(.*)\.html$)
RewriteCond %{HTTPS} off
RewriteRule ^(.*) https://${NGINX_FQDN[0]}/\$1 [R=301,L]
EOF

# [Apache] Reset Permission: User(6)/UserGroup(6)/Other(4)
chown -R ${APACHE_USER}:${LOG_GROUP} ${DIR_APACHE_LOG}
find ${DIR_APACHE_LOG} -type d -exec chmod 775 {} \;
find ${DIR_APACHE_LOG} -type f -exec chmod 664 {} \;

# [Apache] Configure core config
if [ -f -e ${CONFIG_OS_APACHE} ] && [ ! -e ${CONFIG_OS_APACHE}.bak ]; then
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
Listen 8888
Listen ${MACKEREL_PORT_APACHE}

ExtendedStatus On

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
LogFormat "%v:%p %h %l %u %{%Y/%m/%d %T %Z}t \"%r\" %>s %O \"%{Referer}i\" \"%{User-Agent}i\"" vhost_combined
LogFormat "%h %l %u %{%Y/%m/%d %T %Z}t \"%r\" %>s %O \"%{Referer}i\" \"%{User-Agent}i\"" combined
LogFormat "%h %l %u %{%Y/%m/%d %T %Z}t \"%r\" %>s %O" common
LogFormat "%{Referer}i -> %U" referer
LogFormat "%{User-agent}i" agent

ErrorLogFormat "[%{%Y/%m/%d %T %Z}t] [%l] [pid %P] [client %a ] [referer %{Referer}i ] %F: %E: %M"
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
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>

<VirtualHost *:8888>
    ServerAdmin webmaster@localhost
    ServerName localhost:8888

    LogLevel warn
    ErrorLog ${DIR_APACHE_LOG}/error.log
    CustomLog ${DIR_APACHE_LOG}/access.log combined

    DocumentRoot ${DOCPATH_TOOLS}
    <Directory ${DOCPATH_TOOLS}>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>

<VirtualHost *:${MACKEREL_PORT_APACHE}>
    ServerAdmin webmaster@localhost
    ServerName localhost:${MACKEREL_PORT_APACHE}

    LogLevel warn
    ErrorLog ${DIR_APACHE_LOG}/error.log
    CustomLog ${DIR_APACHE_LOG}/access.log combined

    DocumentRoot ${DOCPATH_HTTP}
    <Directory ${DOCPATH_HTTP}>
        Options All
        AllowOverride All
        Require all granted
    </Directory>

    <Location "${MACKEREL_PATH_APACHE}">
        SetHandler server-status
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

#region Nginx

# [Nginx] User to APACHE_USER
chown -R ${APACHE_USER}:${LOG_GROUP} ${DIR_NGINX_LOG}

# [Nginx] Configure core config
if [ -f -e ${CONFIG_OS_NGINX} ] && [ ! -e ${CONFIG_OS_NGINX}.bak ]; then
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
# https://github.com/oauth2-proxy/oauth2-proxy/blob/master/contrib/local-environment/nginx.conf
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
    server_name localhost;
    location ${MACKEREL_PATH_NGINX} {
        stub_status on;
        access_log off;
        allow 127.0.0.1;
        deny all;
    }
}
EOF
rm -f /etc/nginx/sites-enabled/default
ln -s ${CONFIG_NGINX_DEFAULT} /etc/nginx/sites-enabled/default

# [Nginx] Configure https 443
# Note: [] is not needed in if. Format is 'if "${boolean}"''
nginx_oauth2proxy=
nginx_vscode=
nginx_tools=

if [ -n "${OAUTH2_CLIENT}" ] && [ -n "${OAUTH2_SECRET}" ]; then
    nginx_oauth2proxy=$(
        cat <<EOF
        auth_request /oauth2/auth;
        error_page 401 =403 /oauth2/sign_in;
        auth_request_set \$auth_cookie \$upstream_http_set_cookie;
        add_header Set-Cookie \$auth_cookie;
EOF
    )
fi

if "${ENABLE_VSCODE}"; then
    nginx_vscode=$(
        cat <<EOF
    location ${PATH_VSCODE}/ {
        ${nginx_oauth2proxy}

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

# Enable if oauth is enabled
if "${ENABLE_TOOLS}" && [ -n "${OAUTH2_CLIENT}" ] && [ -n "${OAUTH2_SECRET}" ]; then
    nginx_tools=$(
        cat <<EOF
    location ${PATH_TOOLS}/ {
        ${nginx_oauth2proxy}

        proxy_pass http://127.0.0.1:8888/;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$remote_addr;
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

    ${nginx_vscode}

    ${nginx_tools}

    location = /oauth2/auth {
        proxy_pass http://127.0.0.1:${PORT_OAUTH2PROXY};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-Uri \$request_uri;
        proxy_set_header Content-Length "";
        proxy_pass_request_body off;
    }

    location /oauth2/ {
        proxy_pass http://127.0.0.1:${PORT_OAUTH2PROXY};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Auth-Request-Redirect \$scheme://\$host\$request_uri;
    }

    location / {
        proxy_pass http://127.0.0.1:${PORT_HTTPS}/;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_set_header Cookie \$http_cookie;
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
cmd_mysqldmp=""
for db in "${BACKUP_DB[@]}"; do
    cmd_mysqldmp+="        "
    cmd_mysqldmp+="/usr/bin/mysqldump \$MYSQLDUMPOPTION -h localhost -u root ${db} | gzip > ${DIR_MYSQLDUMP_LOG}/${db}.sql.gz"
    cmd_mysqldmp+=$'\n'
done
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
${cmd_mysqldmp}
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

if [ -n "${MACKEREL_APIKEY}" ]; then
    echo "Setting up mackerel..."

    cat <<EOF >${CONFIG_OS_MACKEREL}
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


[plugin.checks.user_ssh]
command = ["check-log", "--file", "/var/log/auth.log", "--pattern", "session opened", "--exclude", "(cron|sudo|runuser|systemd-user):session", "--return"]
prevent_alert_auto_close = true

[plugin.checks.user_add]
command = ["check-log", "--file", "/var/log/auth.log", "--pattern", "new user", "--return"]
prevent_alert_auto_close = true

[plugin.checks.user_password]
command = ["check-log", "--file", "/var/log/auth.log", "--pattern", "password changed", "--return"]
prevent_alert_auto_close = true


[plugin.checks.login_vscode]
command = ["check-log", "--file", "${DIR_NGINX_LOG}/access.log", "--pattern", "POST ${PATH_VSCODE}/login HTTP/1\\\\..\" 302"]

[plugin.checks.login_tools]
command = ["check-log", "--file", "${DIR_NGINX_LOG}/access.log", "--pattern", "GET ${PATH_TOOLS}/ HTTP/1\\\\..\" 200"]


# Plugin for Linux
[plugin.metrics.linux]
command = "mackerel-plugin-linux"

# Plugin for Apache2 (mod_status)
[plugin.metrics.apache2]
command = "mackerel-plugin-apache2 -p ${MACKEREL_PORT_APACHE} -s ${MACKEREL_PATH_APACHE}?auto"

# Plugin for Nginx (stub_status)
[plugin.metrics.nginx]
command = "mackerel-plugin-nginx -port ${MACKEREL_PORT_NGINX} -path ${MACKEREL_PATH_NGINX}"

# Plugin for MySQL
# By default, the plugin accesses MySQL on localhost by 'root' with no password.
[plugin.metrics.mysql]
command = "mackerel-plugin-mysql"


[plugin.metrics.accesslog-apache]
command = "mackerel-plugin-accesslog ${DIR_APACHE_LOG}/access.log"

[plugin.metrics.accesslog-nginx]
command = "mackerel-plugin-accesslog ${DIR_NGINX_LOG}/access.log"


# Plugin for Squid
[plugin.metrics.squid]
command = "mackerel-plugin-squid -port=8080"
EOF

    if "${RESTART}"; then
        systemctl disable --now mackerel-agent
        systemctl enable --now mackerel-agent
    else
        systemctl restart --now mackerel-agent
    fi
fi

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
#Service = "-sshd"
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
systemctl disable --now oauth2-proxy

if "${RESTART}"; then
    systemctl disable --now code-server@${USERNAME}
    systemctl disable --now oauth2-proxy@${USERNAME}
    systemctl disable --now mysql
    systemctl disable --now apache2
    systemctl disable --now nginx
fi

systemctl enable --now code-server@${USERNAME}
systemctl enable --now oauth2-proxy@${USERNAME}
systemctl enable --now mysql
systemctl enable --now apache2
systemctl enable --now nginx
systemctl enable --now php7.4-fpm

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
