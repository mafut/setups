#!/bin/bash

#region squid_setup
# $1: 0=false or 1=true
function squid_setup() {
    # [Proxy] Setup squid
    CONFIG=/etc/squid/squid.conf
    cat <<EOF >${CONFIG}
http_port ${HOMEPORT}
coredump_dir /var/spool/squid

acl localnet src 10.0.0.0/8
acl localnet src 172.16.0.0/12
acl localnet src 192.168.0.0/16
acl localnet src fc00::/7
acl localnet src fe80::/10
acl localnet src ${HOMEIP}/32
http_access allow localnet
http_access allow localhost

acl microsoft dstdomain .office.com .office.net .office365.com .live.com .windows.com .windows.net .microsoft.com .skype.com .microsoftonline.com .1drv.ms .sharepoint.com .sharepoint-df.com
acl apple dstdomain .apple.com .icloud.com .mzstatic.com
acl google dstdomain .google.com .googleapis.com
acl iphoneapp dstdomain .slack.com .uber.com .amazon.com .amazone.co.jp
acl plex dstdomain .plex.tv
http_access allow microsoft
http_access allow apple
http_access allow google
http_access allow iphoneapp
http_access allow plex

acl SSL_ports port 443
acl CONNECT method CONNECT
http_access deny CONNECT !SSL_ports

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
http_access deny !Safe_ports

acl blocked_status http_status 500- 400-407
access_log none blocked_status

refresh_pattern ^ftp:               1440    20% 10080
refresh_pattern ^gopher:            1440    0%  1440
refresh_pattern -i (/cgi-bin/|\?)   0       0%  0
refresh_pattern .                   0       20% 4320

forwarded_for off
request_header_access X-Forwarded-For deny all
request_header_access Via deny all
request_header_access Cache-Control deny all
visible_hostname unknown
EOF

    if [ -e $1 ] && [ $1 -eq 1 ]; then
        cat <<EOF >>${CONFIG}

auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/.htpasswd
auth_param basic children 5
auth_param basic realm Squid Basic Authentication
auth_param basic credentialsttl 24 hours
auth_param basic casesensitive off
acl password proxy_auth REQUIRED
http_access allow password
EOF
    fi

    cat <<EOF >>${CONFIG}

http_access deny all
EOF

}
#endregion

#region ufw_setup
function ufw_setup() {
    # Reset Firewall
    ufw disable
    ufw allow ${HOMEPORT}

    # Enable Port Forward Policy
    CONFIG=/etc/default/ufw
    sed "s|DEFAULT_FORWARD_POLICY=\\\"DROP\\\"|DEFAULT_FORWARD_POLICY=\\\"ACCEPT\\\"|g" ${CONFIG} | sponge ${CONFIG}

    CONFIG=/etc/ufw/before.nat.rules
    cat <<EOF >${CONFIG}
*nat
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s 192.168.1.0/24 -o ens3 -j MASQUERADE
COMMIT
EOF

    CONFIG=/etc/ufw/before.rules
    sed "s|# drop INVALID packets|-A ufw-before-input -p 47 -j ACCEPT\n-A ufw-before-forward -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu\n#drop INVALID packets|g" ${CONFIG} | sponge /etc/ufw/before.filter.rules
    cat /etc/ufw/before.nat.rules /etc/ufw/before.filter.rules >${CONFIG}

    ufw --force enable
}
#endregion

if [ $# -ge 2 ]; then
    USERNAME=$SUDO_USER
    if [ -z "${USERNAME}" ]; then
        echo "Can't get User Name"
        exit 1
    fi

    HOMENETWORK=$2
    if [ -z "${HOMENETWORK}" ]; then
        echo "Can't get allowed host"
        exit 1
    fi

    HOMEIP=$(getent hosts ${HOMENETWORK} | awk '{print $1}')
    if [ -z "${HOMENETWORK}" ]; then
        echo "Can't get IP of ${HOMENETWORK}"
        exit 1
    fi


    HOMEPORT=$3
    if [ -z "${HOMEPORT}" ]; then
        echo "Can't get allowed port"
        exit 1
    fi

    cat <<EOF
[Configuration]
Allowed: ${HOMENETWORK}
Resolved: ${HOMEIP}
Port: ${HOMEPORT}

EOF

    # Install packages
    apt-get -y update
    apt-get -y upgrade
    apt-get -y install ufw squid apache2-utils moreutils

    # Create .htpasswd
    if [ -e "$4" ]; then
        htpasswd -b -c /etc/squid/.htpasswd proxy $4
    fi

    case $1 in
    ubuntu)
        # Stop Services at the first
        systemctl stop squid

        ufw_setup
        if [ -e "$4" ]; then
            squid_setup 1
        else
            squid_setup 0
        fi

        # Add Auto startup and Start service
        systemctl enable squid
        systemctl restart squid
        ;;
    synology)
        if [ -e "$4" ]; then
            squid_setup 1
        else
            squid_setup 0
        fi
        ;;
    *) exit 1 ;;
    esac

    exit 0
else
    cat <<EOF
[Usage for Ubuntu]
1. git clone https://github.com/mafut/setupscripts.git
2. sudo proxy/setup.sh ubuntu [allowed host] [port] [password(option)]

[Usage for Synology]
1. Create "ubuntu/squid" docker container (host network instead of bridge)
2. SSH to synology
3. sudo docker exec it [container] bash
4. sudo apt-get install git
5. git clone https://github.com/mafut/setupscripts.git
6. sudo proxy/setup.sh synology [allowed host] [port] [password(option)]

EOF
fi
