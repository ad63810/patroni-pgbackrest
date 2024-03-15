#!/bin/bash
GetIP () {
#-----------------------------------------------------------------------------------------#
#                           Récupération de l'IP principale du serveur
#-----------------------------------------------------------------------------------------#
        set $TRACE
        #IPADDR=$(ip -f inet addr show eth0 | grep -Po 'inet \K[\d.]+')
        #IPADDR=$(basename $(find /sys/class/net -type l | grep -v '/lo'))
        IPADDR=$(hostname -I | tr -d ' ')
        if [[ "$IPADDR" = "" ]]
        then
                IPADDR=$(ip -f inet addr show ens18 | grep -Po 'inet \K[\d.]+')
        fi
}
GenerateService () {
#-----------------------------------------------------------------------------------------#
#                            Startup script generation for systemd
#-----------------------------------------------------------------------------------------#
        set $TRACE
        if [[ "$INSTALLTYPE" = "server" ]]
        then
                OPTION="-bootstrap-expect 3"
        else
                OPTION=""
        fi
        echo "===> Generating service"
        cat <<EOF> /etc/systemd/system/consul.service
[Unit]
Description=Consul Service Discovery Agent
Documentation=https://www.consul.io/
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=consul
Group=consul
ExecStart=/usr/local/bin/consul agent -config-dir=/etc/consul.d

ExecReload=/bin/kill -HUP $MAINPID
KillSignal=SIGINT
TimeoutStopSec=5
Restart=on-failure
SyslogIdentifier=consul

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable consul.service
        systemctl restart consul.service
}
#
InstallClient () {
#-----------------------------------------------------------------------------------------#
#                           Client installation and configuration
#-----------------------------------------------------------------------------------------#
        echo "===> Installing client"
        InstallConsul
        GenerateConfig
        GenerateService
}
#
InstallServer () {
#-----------------------------------------------------------------------------------------#
#                           server installation and configuration
#-----------------------------------------------------------------------------------------#
        echo "===> Installing server"
        InstallConsul
        GenerateConfig
        GenerateService
}
#
#-----------------------------------------------------------------------------------------#
#                           consul software installation
#-----------------------------------------------------------------------------------------#
InstallConsul ()
{
        set $TRACE
        echo "===> Installing consul package"
        systemctl stop consul
        systemctl disable consul
        rm -F /etc/systemd/system/multi-user.target.wants/consul.service
        apt-get update
        apt-get install unzip
        rm -Rf   /usr/src/consul /opt/consul /var/lib/consul /etc/consul.d  /var/log/consul
        mkdir -p /usr/src/consul /opt/consul /var/lib/consul /etc/consul.d  /var/log/consul
        id consul > /dev/null
        if [[ $? -ne 0 ]]
        then
                echo "===> Creating consul user"
                useradd -m -d /var/lib/consul -s /bin/bash consul
                passwd -u consul
                passwd consul
                chown consul:consul /var/consul
        fi
        cd /usr/src/consul && \
        wget https://releases.hashicorp.com/consul/$VERSION/consul_$VERSION\_linux_amd64.zip && \
             unzip consul_$VERSION\_linux_amd64.zip && \
        cp -R consul /opt/consul && \
        rm -f /usr/local/bin/consul && \
           ln -s /opt/consul/consul /usr/local/bin/consul # to make it available in the standard PATH && \
        rm consul_$VERSION\_linux_amd64.zip && \
           echo "consul:C0NsUl" | chpasswd # 0 est un zero
        chown -R consul:consul /var/lib/consul /etc/consul.d  /var/log/consul
        rm -f /var/lib/consul/serf/local.keyring
        systemctl enable  consul
        systemctl restart consul
}
#
GenerateConfig () {
#-----------------------------------------------------------------------------------------#
#                           Génération du fichier de configuration
#-----------------------------------------------------------------------------------------#
        set $TRACE
        echo "===> Ge▒eération de la configuratn"
        killall consul
        if [[ "$KEY" = "" ]]
        then
                KEY=$(consul keygen)
                echo "Comme vous n'avez pas specifie de clef (parametre -k)"
                echo ""
                echo "la clef $KEY a ete generee automatiquement"
                echo ""
        fi
        echo "Vous devrez utiliser l'option -k $KEY pour l'installation des autres noeuds et agents"
        #
        GetIP
        #
        case "$INSTALLTYPE" in
                "bootstrap") BOOTSTRAP='"bootstrap": true,'
                             SERVER='"server": true'            ;;
                "server")    BOOTSTRAP='"bootstrap_expect": 1,'
                             SERVER='"server": true'            ;;
                "client")    BOOTSTRAP=""
                             SERVER='"server": false'           ;;
                *)           BOOTSTRAP=""
                             SERVER='"server": false'           ;;
        esac
        cat <<EOF>  /etc/consul.d/config.json || error
{
    "node_name": "$NODENAME",
    "encrypt": "$KEY",
    "disable_keyring_file": true,
    "advertise_addr": "$IPADDR",
    "bind_addr": "$IPADDR",
    "datacenter": "$DCNAME",$BOOTSTRAP
    $SERVER,
    "client_addr": "0.0.0.0",
    "data_dir": "/var/lib/consul",
    "domain": "patroni",
    "enable_script_checks": true,
    "dns_config": {
        "enable_truncate": true,
        "only_passing": true
    },
    "log_rotate_bytes": 100000000,
    "leave_on_terminate": false,
    "enable_syslog": false,
    "log_level": "INFO",
    "log_file": "/var/log/consul/consul.log",
    "log_level": "INFO",
    "log_rotate_duration": "24h",
    "log_rotate_max_files": 7,
    "rejoin_after_leave": true,
    "retry_join": ["dcs1","dcs2","dcs3"],
    "start_join": ["dcs1","dcs2","dcs3"],
    "ui": true
}
EOF
}
#-----------------------------------------------------------------------------------------#
#                            Installation parameters parsing
#-----------------------------------------------------------------------------------------#
unset DCNAME VERSION KEY SERVER_LIST INSTALLTYPE TRACE
while getopts bcd:k:sv:S:xn:p OPT
do
        case "$OPT" in
                "b") INSTALLTYPE="bootstrap" ;;
                "c") INSTALLTYPE="client"    ;;
                "s") INSTALLTYPE="server"    ;;
                "p") INSTALLTYPE="package"   ;;
                "d") DCNAME="$OPTARG"        ;;
                "k") KEY="$OPTARG"           ;;
                "S") SERVER_LIST="$OPTARG"   ;;
                "v") VERSION="$OPTARG"       ;;
                "x") TRACE="-x"              ;;
                "n") NODENAME="$OPTARG"      ;;
                *)   echo "===> Type d'installation $OPT invalide"
                     exit 1
                     ;;
        esac
done
#VERSION=${VERSION:-"1.6.1"}
VERSION=${VERSION:-"1.17.2"}
DCNAME=${DCNAME:-"dc1"}
TRACE=${TRACE:-"+x"}
SERVER_LIST=${SERVER_LIST:-'"dcs1","dcs2","dcs3"'}
if [[ "$INSTALLTYPE" != "package" ]]
then
        HOSTNAME=$(hostname)
        while [[ "$NODENAME" = "" ]]
        do
                echo "Quel est le nom du node a créer  <ENTER> = $HOSTNAME par défaut"
                read NODENAME
                NODENAME=${NODENAME:-$HOSTNAME}
        done
fi
echo "===> Vous installez un $INSTALLTYPE $VERSION sur le datacenter $DCNAME noeud $NODENAME du cluster $SERVER_LIST"
echo ""
echo "                                 faites <ENTER> pour continuer sinon faites <CTRL-C> pour abandonner"
read
#
#
service consul stop
updatedb
rm -Rf $(locate consul | grep -v $0)
updatedb
locate consul

case "$INSTALLTYPE" in
        "package")   InstallConsul ;;
        "client")    InstallClient ;;
        "bootstrap") InstallServer ;;
        "server")    InstallServer ;;
        *)           echo "===> Type d'installation $INSTALLTYPE invalide spécifiez -s pour server -c pour client"
                     exit 1
                     ;;
esac
