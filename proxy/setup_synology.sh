#!/bin/bash

function init(){
    # APT update/upgrade
    apt-get -y update
    apt-get -y upgrade
    
    # Install packages
    apt-get -y --force-yes install vim apache2-utils
}

function setup(){     
    # Create .htpasswd
    htpasswd -b -c /etc/squid/.htpasswd proxy ${PASS}
    
    # [Proxy] Setup squid
    HOMEIP=$(getent hosts ${HOMENETWORK} | awk '{print $1}')
    CONFIG=/etc/squid/squid.conf
    cp -f ${CONFIG} ${CONFIG}.bak
    cat << EOF > ${CONFIG}
acl localnet src 10.0.0.0/8
acl localnet src 172.16.0.0/12
acl localnet src 192.168.0.0/16
acl localnet src fc00::/7
acl localnet src fe80::/10
acl localnet src ${HOMEIP}/32

acl microsoft dstdomain .office.com .office.net .office365.com .live.com .windows.com .windows.net .microsoft.com .skype.com .microsoftonline.com .1drv.ms .sharepoint.com .sharepoint-df.com
acl apple dstdomain .apple.com .icloud.com .mzstatic.com
acl google dstdomain .google.com .googleapis.com
acl iphoneapp dstdomain .slack.com .uber.com .amazon.com .amazone.co.jp
acl plex dstdomain .plex.tv

acl SSL_ports port 443
acl Safe_ports port 80 # http
acl Safe_ports port 443 # https
acl Safe_ports port 25 # exchange smpt
acl Safe_ports port 587 # exchange smpt
acl Safe_ports port 143 # exchange imap4
acl Safe_ports port 993 # exchange imap4
acl Safe_ports port 995 # exchange pop3
acl Safe_ports port 5223 # Apple push
acl Safe_ports port 1900 # Plex DLNA
acl Safe_ports port 5353 # Plex Bonjour
acl Safe_ports port 1025-65535 # unregistered ports

acl CONNECT method CONNECT

http_access deny !Safe_ports
http_access deny CONNECT !SSL_ports

http_access allow microsoft
http_access allow apple
http_access allow google
http_access allow iphoneapp
http_access allow plex
http_access allow localnet
http_access allow localhost

http_port 8080

coredump_dir /var/spool/squid

refresh_pattern ^ftp:               1440    20% 10080
refresh_pattern ^gopher:            1440    0%  1440
refresh_pattern -i (/cgi-bin/|\?)   0       0%  0
refresh_pattern .                   0       20% 4320

forwarded_for off
request_header_access X-Forwarded-For deny all
request_header_access Via deny all
request_header_access Cache-Control deny all

visible_hostname unknown

auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/.htpasswd
auth_param basic children 5
auth_param basic realm Squid Basic Authentication
auth_param basic credentialsttl 24 hours
auth_param basic casesensitive off
acl password proxy_auth REQUIRED
http_access allow password
http_access deny all
EOF
}

if [ $# = 2 ];
then
    # Initialize variables
    PASS=$1
    if [ -z "${PASS}" ];
    then
        echo "Can't get password"
        exit 1
    fi
    
    HOMENETWORK=$2
    if [ -z "${HOMENETWORK}" ];
    then
        echo "Can't get allowed host"
        exit 1
    fi

    init
    setup $1 $2
    exit 0
fi

cat << EOF
[Usage]
1. Create "ubuntu/squid" docker container (host network instead of bridge)
2. SSH to synology
2. sudo docker exec it [container] bash
3. sudo apt-get install git
4. git clone https://github.com/mafut/setupscripts.git
5. sodo proxy/setup_synology.sh [password] [allowed host]
EOF
exit 0