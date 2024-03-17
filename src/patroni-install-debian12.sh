#!/bin/bash
# @(#) ------------------------------------------------------------------------#
# @(#) Produit/Applic.   : PostgreSQL / patroni
# @(#) ------------------------------------------------------------------------#
# @(#) Nom du script     : patroni-install-debian12.sh
# @(#) Fonction          : PostgreSQL PATRONI installation
# @(#) Createur          : A.Desnoyer
# @(#) Date Creation     : 03/03/2024
# @(#) ------------------------------------------------------------------------#
# @(#) Utilisation : patroni-install-debian12.sh
# @(#)
# @(#)
# @(#) ------------------------------------------------------------------------#
# @(#) options     :
# @(#)
# @(#)                -h  (help) will display this header as help information
# @(#)
# @(#)                -v [postgresql version] # Postgresql version (not mendatory)
# @(#)                -x                      # activate script debugging
# @(#)                -i IP
# @(#)                -n NODENAME
# @(#)                -p DBA_PASS
# @(#)                -P Installation d'un noeud de type "primary"
# @(#)                -R Installation d'un noeud de type "replica"
# @(#)                -c Nom du cluster patroni
# @(#)                -v Version de PostgreSQL (13 14 15 16..,)
# @(#) ------------------------------------------------------------------------#
# @(#) Date modification :
# @(#) Commentaires      :
# @(#) Modifie par       :
# @(#) ------------------------------------------------------------------------#
trap 'StopRun' KILL TERM
setColors () {
        set $TRACE
        DEFAULT="\033[0m"         # RESET to default color
        # NORMAL INTENSITY
        GREEN="\033[0;32m"
        RED="\033[0;31m"
        YELLOW="\033[0;33m"
        # BOLD HIGH INTENSITY
        BIRED='\033[1;91m'        # BOLD HIGH RED
        BIGREEN='\033[1;92m'      # BOLD HIGH GREEN
        BIYELLOW='\033[1;93m'     # BOLD HIGH YELLOW
}
help () {
#------------------------------------------------------------------------------#
#       Affichage de l'aide
#------------------------------------------------------------------------------#
        set $TRACE
        awk '/\# \@\(\#\)/ {print substr($0,8)}' $0
        exit
}
StopRun () {
#------------------------------------------------------------------------------#
#                               Arret du script
#------------------------------------------------------------------------------#
        set "$TRACE"
        echo "Script termine !!!"
        exit 2
}
title () {
#------------------------------------------------------------------------------#
#                       Affichage d'un titre encadre en vert
#------------------------------------------------------------------------------#
        set "$TRACE"
        TITLE="$*"
        echo -e "$GREEN"
        COLUMNS=80
        printf '=%.0s' {1..80}
        printf "\n"
        printf "=%*s\n" $(((${#title}+$COLUMNS)/2)) "$TITLE"
        printf '=%.0s' {1..80}
        echo -e "$DEFAULT"
}
displayBanner () {
#------------------------------------------------------------------------------#
#                       Affichage de la banniere PGBACKREST
#------------------------------------------------------------------------------#
        set "$TRACE"
        apt install -y "figlet" > /dev/null 2>&1
        clear
        COLUMNS=$(tput cols)
        echo -e "$GREEN"
        figlet -w $COLUMNS "$*"
        echo -e "$DEFAULT"
}
Msg () {
#------------------------------------------------------------------------------#
#                       Affichage de message formate
#------------------------------------------------------------------------------#
        set "$TRACE"
        MSGLEVEL="$1"
        MSGTEMP="$*"
        shift 1
        MSG="$*"
        case $MSGLEVEL in
             critical|-c) COLOR="$BIRED"  ;;
             warning|-w)  COLOR="$YELLOW" ;;
             info|-i)     COLOR="$GREEN"  ;;
             *)           COLOR="$DEFAULT"
                          MSG="$MSGTEMP"  ;;
        esac
        echo -e "$COLOR $MSG $DEFAULT"
}
Error () {
#------------------------------------------------------------------------------#
#                Affichage de message d'erreur et arret du script
#------------------------------------------------------------------------------#
        set "$TRACE"
        MSG="$*"
        Msg critical "ERREUR $MSG"
        exit 1
}
checkConsul () {
#----------------------------------------------------------------------------
#                       Verification que consul est bien actif
#----------------------------------------------------------------------------
        set "$TRACE"
        title "Verification de consul actif"
        sudo systemctl start consul
        sleep 2
        if ! sudo systemctl status consul >/dev/null
        then
                Error "Consul n'est pas actif : abandon"
        fi
}
GetIP () {
#----------------------------------------------------------------------------
#                  Recuperation de l'adrese IP principale
#----------------------------------------------------------------------------
set "$TRACE"
PARM="$1"
IFACE=$(ip a | awk -F':' '$1=="2" {print $2}' | tr -d ' ')
IFACEIP=$(hostname -I | tr -d ' ')
if [[ "$PARM" != "prompt" ]]
then
        return
fi
#----------------------------------------------------------------------------
#  Demande de l'adresse IP (si l'option "prompt" a l'appel de la fonction
#----------------------------------------------------------------------------
displayBanner "PATRONI" "installation"
while true
do
        IP=$IFACEIP
        echo "Adresse IP de communication : $IP tapez <ENTER> pour confirmer"
        echo "ou saisissez l'adresse que vous désirez ou <CTRL-> pour abandoner"
        read IP
        case "$IP" in
                "")      IP=$IFACEIP
                         break  # Default to eth0 address
                         ;;
                *.*.*.*) ip -f inet addr show | grep -Po 'inet \K[\d.]+' \
                            | grep "$IP"
                         if [[ $? -eq 0 ]]
                         then
                            break  # Adresse existante : OK
                         else
                            clear
                            echo -e "\n$IP inexistante sur cette machine\n"
                         fi
                         ;;
                *)       clear
                         echo -e "\nAdresse IP $IP invaide\n"
                         continue
                         ;;
        esac
done
}
InstallPostgres () {
#----------------------------------------------------------------------------
#                    Installation de PostgreSQL
#----------------------------------------------------------------------------
        set "$TRACE"
        title "Debut installation  POSTGRESQL $PGVERSION"
        # desactivation IPV6
        sysctl -w net.ipv6.conf.all.disable_ipv6=1
        sysctl -w net.ipv6.conf.default.disable_ipv6=1
        sysctl -w net.ipv6.conf.tun0.disable_ipv6=1
        sysctl -w net.ipv6.conf.lo.disable_ipv6=1
        # suppression d'une installation precedente eventuelle
        sudo service patroni stop
        sudo killall patroni
        #sudo service postgresql stop
        #sudo killall postgresql
        sudo apt update -y
        sudo apt-get purge -y '*postgresql*' 2>/dev/null
        sudo rm -Rf /etc/postgresql /var/lib/postgresql /usr/lib/postgresql \
                    /usr/share/postgresql /usr/include/postgresql

        # Installation prerequis
        sudo apt install -y gnupg2

        # Create the file repository configuration:
        sudo echo "deb https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
             > /etc/apt/sources.list.d/pgdg.list

        # Import the repository signing key:
        sudo wget --quiet -O- https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -

        # Update the package lists:
        sudo apt update -y

        # Install PostgreSQL.
        sudo apt-get -y install postgresql-$PGVERSION # postgresql-common postgresql-contrib
        sudo ln -s /usr/lib/postgresql/$PGVERSION/bin/* /usr/sbin/
        sudo ln -s /usr/lib/postgresql/$PGVERSION/bin/* /usr/sbin/
        sudo chown -R postgres:postgres /etc/postgresql /var/lib/postgresql /srv/postgresql
        cd ~postgres
        sudo -u postgres createuser --echo --superuser   dba
        sudo -u postgres createuser --echo --replication repl
        sudo -u postgres createuser --echo --superuser   centreon
        sudo -u postgres psql -c "ALTER USER postgres PASSWORD '"$POSTGRES_PASS"';"
        sudo -u postgres psql -c "ALTER USER centreon PASSWORD '"$DBA_PASS"';"
        sudo -u postgres psql -c "ALTER USER dba      PASSWORD '"$DBA_PASS"';"
        sudo -u postgres psql -c "ALTER USER repl     PASSWORD '"$REPL_PASS"';"
        if [[ "$PGVERSION" = "16" ]]
        then
                systemctl stop posqtgresql
                systemctl disable posqtgresql
        else
                true
                # pg_dropcluster 16 main
        fi
        HBAFILE="/etc/postgresql/$PGVERSION/main/pg_hba.conf"
        cp $HBAFILE $HBAFILE.ori
        echo "=============================================================="
        echo "= Fin d'installation  postgresql faites <ENTER> pour continuer"
        echo "=============================================================="
        read
}
InstallPatroniAPT () {
#----------------------------------------------------------------------------
#                         Installation de Patroni
#----------------------------------------------------------------------------
        set "$TRACE"
        title "Debut installation de PATRONI"
        GetIP
        #--------------------------------------------------------------------
        #                 suppression ancienne configuration
        #--------------------------------------------------------------------
        sudo systemctl stop patroni
        sudo rm -Rf /etc/patroni
        sudo aptitude purge   -y patroni
        sudo rm -f /etc/systemd/system/multi-user.target.wants/patroni.service
        #--------------------------------------------------------------------
        if [[ "$NODETYPE" = "primary" ]]
        then
                # suppression de la clef du cluster dans consul
                sudo consul kv delete --recurse service/$CLUSTERNAME
                sleep 5
                #
        fi
        #--------------------------------------------------------------------
        #
        sudo apt-get  install -y aptitude
        sudo aptitude install -y python3-psycopg2
        sudo aptitude install -y python3-psycopg
        sudo aptitude install -y python3-consul2
        #--------------------------------------------------------------------
        # PostgreSQL s'executera comme sous process de patroni et peut
        # entrer en conflit avec le service cree par l'installation standard
        # de PostgreSQL : donc on le desactive.
        #--------------------------------------------------------------------
        sudo systemctl stop postgresql
        sudo systemctl disable postgresql
        #
        sudo aptitude  install -y patroni
        sudo systemctl enable patroni
        #sudo systemctl start patroni
        #
        GeneratePatroniConfig
        #
        if [[ "$NODETYPE" = "replica" ]]
        then
                echo "Suppression du cluster genere par l'installation postgresql"
                sudo rm -Rf "/var/lib/postgresql/$PGVERSION/main"
        fi
        sudo systemctl restart patroni
}
GeneratePatroniConfig ()
#----------------------------------------------------------------------------
#                    Generation de la configuration Patroni
#----------------------------------------------------------------------------
{
        set "$TRACE"
        title "Configuration de PATRONI"
        #
        sudo chown -R postgres:postgres /etc/postgresql /var/lib/postgresql
        #
        IPCIDR=$(hostname -I | cut -d. -f1-3)".0/24"
        HBAFILE="/etc/postgresql/$PGVERSION/main/pg_hba.conf"
        mkdir -p /etc/patroni
        sudo cat <<EOF> /etc/patroni/patroni.yml
scope: $CLUSTERNAME
name: $NODENAME

restapi:
  listen: 0.0.0.0:8008
  connect_address: $IP:8008

consul:
  host: $IP:8500

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    check_timeline: true
    synchronous_mode: true
    synchronous_node_count: 2
    postgresql:
      use_pg_rewind: true
      remove_data_directory_on_rewind_failure: true
      remove_data_directory_on_diverged_timelines: true
      use_pg_rewind: true
      use_slots: true
      parameters:
        archive_command: /usr/bin/pgbackrest --stanza=$CLUSTERNAME archive-push %p
        archive_mode: 'on'
        archive_timeout: '5min'
        checkpoint_timeout: 30
        client_min_messages: LOG
        hot_standby: 'on'
        log_connections: true
        log_destination: syslog
        log_directory: /var/log/postgresql
        log_filename: postgresql-%Y-%m-%d_%H%M%S.log
        log_min_duration_statement: 0
        log_min_error_statement: DEBUG5
        log_min_messages: INFO
        log_rotation_age: 1440
        log_statement: all
        log_truncate_on_rotation: true
        logging_collector: true
        max_relication_slots: 6
        max_wal_senders: 16
        wal_keep_segment: 128
        wal_level: replica
      pgbackrest:
        command: /usr/bin/pgbackrest --stanza=$CLUSTERNAME --log-level-file=detail --delta restore
        keep_data: true
        no_params: true
      recovery_conf:
        restore_command: /usr/bin/pgbackrest --stanza=$CLUSTERNAME archive-get %f %p
      use_slots: true

  initdb: UTF8

  initdb:
    - encoding: UTF8
    - local: UTF8
    - data-checksums

  pg_hba:
##############################################################################
#              configuration generee par l'installation patroni
##############################################################################
# TYPE  DATABASE        USER            ADDRESS                 METHOD
  - local   all             postgres                                peer
  - local   all             all                                     peer
  - host    dba             all             127.0.0.1/8             trust
  - host    dba             all             0.0.0.0/0               trust
  - host    dba             all             ::1/128                 trust
  - local   replication     all                                     peer
  - host    replication     all             127.0.0.1/8             md5
  - host    replication     all             127.0.0.1/8             scram-sha-256
  - host    replication     all             ::1/128                 trust
  - host    replication     all             ::1/128                 md5
  - host    replication     all             ::1/128                 scram-sha-256
  - host    replication     repl            0.0.0.0/0               trust
  - host    replication     repl            0.0.0.0/0               md5
  - host    replication     repl            0.0.0.0/0               scram-sha-256
  - host    all             all             127.0.0.1/8             trust
  - host    all             all             127.0.0.1/8             md5
  - host    all             all             127.0.0.1/8             scram-sha-256
  - host    all             all             0.0.0.0/0               trust
  - host    all             all             0.0.0.0/0               md5
  - host    all             all             0.0.0.0/0               scram-sha-256
  - host    all             centreon        $IPCIDR                 trust
  - host    all             haproxy         $IPCIDR                 trust

  users:
    dba:
      password: $POSTGRES_PASS
      options:
        - createrole
        - createdb
    repl:
      password: $REPL_PASS
      options:
        - replication
  pg_ident:
    - superusermapping root postgres dba

postgresql:
  listen: 0.0.0.0:5432
  connect_address: $IP:5432
  data_dir: /var/lib/postgresql/$PGVERSION/main
  config_dir: /etc/postgresql/$PGVERSION/main
  bin_dir: /usr/lib/postgresql/$PGVERSION/bin
  hba_file: /etc/postgresql/$PGVERSION/main/pg_hba.conf

  authentication:

    rewind:
      username: dba
      password: Ijnbgt56+

    replication:
      username: repl
      password: secret

    superuser:
      username: dba
      password: Ijnbgt56+

  parameters:
    unix_socket_directories: '/var/run/postgresql'
    synchronous_commit: "remote_apply"
    synchronous_standby_names: "*"
    autovacuum: 1
    autovacuum_max_workers: 3

  callbacks:
    on_reload:      '/home/scripts/patroni-callback.sh -w -m "Node is reloaded"'
    on_role_change: '/home/scripts/patroni-callback.sh -w -m "Node role as changed"'
    on_stop:        '/home/scripts/patroni-callback.sh -c -m "Node is stopping"'
    on_start:       '/home/scripts/patroni-callback.sh -n -m "Node is starting"'
    on_restart:     '/home/scripts/patroni-callback.sh -n -m "Node is restarting"'

EOF
        #
        generateHBA
        #
        GenerateService
}
generateHBA () {
        sudo cat <<EOF> $HBAFILE
##############################################################################
#              configuration generee par l'installation patroni
##############################################################################
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all             postgres                                peer
local   all             all                                     peer
host    dba             all             127.0.0.1/8             trust
host    dba             all             ::1/128                 trust
host    dba             all             0.0.0.0/0               trust
local   replication     all                                     peer
host    replication     all             127.0.0.1/8             md5
host    replication     all             127.0.0.1/8             scram-sha-256
host    replication     all             ::1/128                 trust
host    replication     all             ::1/128                 md5
host    replication     all             ::1/128                 scram-sha-256
host    replication     repl            0.0.0.0/0               trust
host    replication     repl            0.0.0.0/0               md5
host    replication     repl            0.0.0.0/0               scram-sha-256
host    all             all             127.0.0.1/8             trust
host    all             all             127.0.0.1/8             md5
host    all             all             127.0.0.1/8             scram-sha-256
host    all             all             0.0.0.0/0               trust
host    all             all             0.0.0.0/0               md5
host    all             all             0.0.0.0/0               scram-sha-256
host    all             centreon        $IPCIDR                 trust
host    all             haproxy         $IPCIDR                 trust
EOF
#
}
GenerateService () {
#----------------------------------------------------------------------------
#                         Generation du service Patroni
#----------------------------------------------------------------------------
        set "$TRACE"
        title "Generation du service systemd patroni"
        sudo cat <<EOF> /etc/systemd/system/patroni.service
[Unit]
Description=Runners to orchestrate a high-availability PostgreSQL
After=syslog.target network.target

[Service]
Type=simple

User=postgres
Group=postgres

Environment="PATH=/usr/bin:/bin:/usr/local/bin:/usr/local/games:/usr/games"
ExecStart=/usr/bin/patroni /etc/patroni/patroni.yml

KillMode=process

TimeoutSec=30

Restart=no

[Install]
WantedBy=multi-user.target
EOF
        sudo systemctl daemon-reload
        sudo systemctl enable patroni
        sudo systemctl start  patroni
        #--------------------------------------------------------------------
        sudo cat <<EOF2> /etc/systemd/system/patroni-switchover.service
[Unit]
Description=Automatic patroni switchover in case of parent website is down
StartLimitIntervalSec=0
[Service]
Type=simple
Restart=always
RestartSec=1
User=root
ExecStart=/bin/bash /srv/v3/scripts/patroni-switchover.sh

[Install]
WantedBy=multi-user.target
EOF2
        sudo systemctl daemon-reload
        sudo systemctl enable patroni-switchover
        sudo systemctl start patroni-switchover
        #--------------------------------------------------------------------
        #   Generation du script /etc/profile.d/patronictl.sh
        #--------------------------------------------------------------------
        # script d'export de la variable pour eviter d'avoir a specifier
        # le fichier de config patronictl a chaque fois.
        #--------------------------------------------------------------------
        sudo cat <<EOF3> /etc/profile.d/patronictl.sh
#--------------------------------------------------------------------
# genere par le script $THISSCRIPT
#--------------------------------------------------------------------
# script d'export de la variable pour eviter d'avoir a specifier
# le fichier de config patronictl a chaque fois.
#--------------------------------------------------------------------
export PATRONICTL_CONFIG_FILE=/etc/patroni/patroni.yml
EOF3
        . /etc/profile.d/patronictl.sh
        sleep 5
        patronictl list
}
#----------------------------------------------------------------------------
#                              M   A   I   N
#----------------------------------------------------------------------------
unset IP DBA_PASS TRACE NODENAME $NODETYPE $CLUSTERNAME
while getopts hi:n:p:PRs:x OPT
do
        case "$OPT" in
                h) help                  ;;
                i) IP="$OPTARG"          ;;
                n) NODENAME="$OPTARG"    ;;
                p) DBA_PASS="$OPTARG"    ;;
                P) NODETYPE="primary"    ;;
                R) NODETYPE="replica"    ;;
                c) CLUSTERNAME="$OPTARG" ;;
                v) PGVERSION="$OPTARG"   ;;
                x) TRACE="-x"            ;;
        esac
done
#----------------------------------------------------------------------------
#                          Initialisation de variables
#----------------------------------------------------------------------------
TRACE=${TRACE:-"+x"}
set "$TRACE"
set $TRACE
THISSCRIPT=$(basename $0)
setColors
#
checkConsul # verification si consul est actif avant de continuer
#
#----------------------------------------------------------------------------
if [[ "$IP" = "" ]]
then
        GetIP "prompt"
fi
PGVERSION=${PGVERSION:-15}
#
POSTGRES_PASS=${POSTGRES_PASS:-"Ijnbgt56+"}
DBA_PASS=${DBA_PASS:-"Ijnbgt56+"}
REPL_PASS=${REPL_PASS:-"secret"}
#
while [[ "$CLUSTERNAME" = "" ]]
do
        echo "Quel est le nom du cluster PATRONI a utiliser  ? (parametre -c a l'appel du script)"
        read CLUSTERNAME
done
while [[ "$NODENAME" = "" ]]
do
        echo "Quel est le nom du noeud a creer ? (parametre -n a l'appel du script)"
        read NODENAME
done
while [[ "$NODETYPE" = "" ]]
do
        echo "Quel est le type d'installation  primary (p) ou replica (r)"
        read REP
        case "$REP" in
                r*) NODETYPE="replica" ;;
                p*) NODETYPE="primary" ;;
        esac
done
echo -e "$BIYELLOW"
echo "===> Vous installez Patroni cluster"
echo ""
echo "                    nom de cluster        : $CLUSTERNAME"
echo ""
echo "                    noeud                 : $NODENAME"
echo "                    Type de noeud         : $NODETYPE"
echo ""
echo "                    mot de passe DBA      : $DBA_PASS"
echo "                    mot de passe REPL     : $REPL_PASS"
echo "                    mot de passe POSTGRES : $POSTGRES_PASS"
echo ""
echo "                    version postgresql    : $PGVERSION"
echo ""
echo "             <ENTER> pour continuer sinon <CTRL-C> pour abandonner"
echo -e "$DEFAULT"
read
#
#----------------------------------------------------------------------------
#                         Install basic necessary tools
#----------------------------------------------------------------------------
apt-get install -y sudo wget
#----------------------------------------------------------------------------
#                             Start installation
#----------------------------------------------------------------------------
InstallPostgres
#
InstallPatroniAPT
#
