#!/bin/bash
# @(#) ------------------------------------------------------------------------#
# @(#) Produit/Applic.   : Utilitaires postgresql / patroni
# @(#) ------------------------------------------------------------------------#
# @(#) Nom du script     : pgbackrest-install.sh
# @(#) Fonction          : installation de pgbackrest sur erveur ou client
# @(#) Createur          : A.Desnoyer
# @(#) Date Creation     : 25/02/2024
# @(#) ------------------------------------------------------------------------#
# @(#) Utilisation : pgbackrest -c -I 111.111.111.111
# @(#)
# @(#)               pgbackrest -b -n "pg1 pg1 p3" -i "1.1.1.1 2.2.2.2 3.3.3.3"
# @(#)
# @(#) options     : -b   pour installation sur serveur de backup
# @(#)               -n "noms patroni des serveur postgresql"
# @(#)               -i "suivi par les adresses IP des serveurs postgresql"
# @(#)
# @(#)               -c pour installation sur un client (noeud postgresql)
# @(#)               -I suivi par l'adresse IP du serveur de sauvegarde
# @(#)
# @(#)               -x pour activer la trace de debugging de ce  script
# @(#) ------------------------------------------------------------------------#
# @(#) Date modification :
# @(#) Commentaires      :
# @(#) Modifie par       :
# @(#) ------------------------------------------------------------------------#
trap 'StopRun' KILL TERM
Help () {
#------------------------------------------------------------------------------#
#                               Affichage de l'aide
#------------------------------------------------------------------------------#
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
        GREEN="\033[0;32m"
        RED="\033[0;31m"
        BIRED='\033[1;91m'
        YELLOW="\033[0;33m"
        DEFAULT="\033[0m"
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
#               Affichage d'un message en rouge et arret du script
#------------------------------------------------------------------------------#
        set "$TRACE"
        MSG="$*"
        Msg critical "ERROR : $MSG"
        exit 1
}
genKey_Server () {
#------------------------------------------------------------------------------#
#       Génération de la clef SSH du user postgres local (serveur backup)
#------------------------------------------------------------------------------#
        set "$TRACE"
        #
        #----------------------------------------------------------------------#
        sudo -iu postgres rm -f .ssh/id_rsa .ssh/id_rsa.pub
        title "Backup server postgres user SSH key Creation"
        sudo -u postgres ssh-keygen -t rsa -b 4096 -f ~postgres/.ssh/id_rsa \
             -C "pgbackrest-server" -N '' <<<''
        #
        #----------------------------------------------------------------------#
        genKeys_Clients
        #
        SSHOK=0
        NODESCOUNT=$(echo $NODESLIST | wc -w)
        SERVERIP=$(hostname -I)
        #
        clear
        echo -e "$YELLOW"
        echo "#----------------------------------------------------------------"
        echo "#    A T T E N T I O N    A V A N T    D E    C O N T I N U E R"
        echo "#"
        echo "# Copiez la clef ssh suivante dans le fichier authorized_keys"
        echo "# du user 'postgres' SUR CHACUNE des machines clientes $NODESLIST"
        echo "#"
        echo -e "$DEFAULT"
        cat ~postgres/.ssh/id_rsa.pub
        echo -e "$GREEN"
        echo "# suivi de la commande suivante :"
        echo "#"
        echo "# ssh -o 'StrictHostKeyChecking=no' $SERVERIP exit"
        echo "#"
        echo "#----------------------------------------------------------------"
        echo "# Une fois la commande executee sur chaque machine,"
        echo "# pour continuer tapez <ENTER>"
        echo "#----------------------------------------------------------------"
        echo -e "$DEFAULT"
        read
        deployClientsKeys
        SSHOK=0
        SSHOPT="-o ConnectTimeout=3 -o StrictHostKeyChecking=no -o BatchMode=Yes"
        for NODE in $NODESLIST
        do
           echo "verification connection ssh $NODE"
           sudo -iu postgres ssh $SSHOPT postgres@$NODE exit > /dev/null 2>&1
           if [[ $? -eq 0 ]]
           then  # Ajout host fingerprint
              sudo -iu postgres ssh $SSHOPT postgres@$NODE        \
                   ssh $SSHOPT $SERVERIP exit > /dev/null 2>&1 && \
              ((SSHOK=SSHOK+1))
           else
              echo -e "$RED"
              echo "ATTENTION NODE $NODE inaccessible !!! verifiez"
              echo "le fichier .ssh/authorized_keys du serveur $NODE"
              echo -e "$DEFAULT"
              sleep 3
           fi
        done
        if [[ $SSHOK -ne $NODESCOUNT ]]
        then
           Error "Tous les noeuds ne sont pas accessibles via ssh"
        fi
        #
        #
}
genKeys_Clients () {
#------------------------------------------------------------------------------#
#       Génération des clefs ssh pour les clients postgresql
#------------------------------------------------------------------------------#
        set "$TRACE"
        SSHOK=0
        NODESCOUNT=$(echo $NODESLIST | wc -w)
        SSHOPT="-o ConnectTimeout=3 -o StrictHostKeyChecking=no -o BatchMode=Yes"
        #-----------------------------------------------------------------------------
        #     Generation des clefs SSH et ajout clef publique dans authorized_keys
        #-----------------------------------------------------------------------------
        title "SSH clients keys creation for ($NODESLIST)"
        for NODE in $NODESLIST
        do
           echo "New SSH key generation for $NODE (will replace the previous if any)"
           rm -f ~postgres/.ssh/$NODE\_id_rsa
           rm -f ~postgres/.ssh/$NODE\_id_rsa.pub
           #
           sudo -u postgres ssh-keygen -t rsa -b 4096 -f ~postgres/.ssh/$NODE\_id_rsa \
                -C "postgres@$NODE" -N '' <<<''
           #
           # Add the new client public key to the postgres authorized_keys file"
           # so as the postges client user can connect with ssh to the server
           sudo -iu postgres sed -i "/postgres@$NODE/d"    .ssh/authorized_keys
           sudo -iu postgres cat ~postgres/.ssh/$NODE\_id_rsa.pub \
                >> ~postgres/.ssh/authorized_keys
        done
}
deployClientsKeys () {
        #-----------------------------------------------------------------------------
        # Rollout of the SSH keys to the clients for cross connection between them
        #
        # The code bellow manages the rollout for 1, 2 or 3 nodes
        #-----------------------------------------------------------------------------
        set "$TRACE"
        #
        # Deletes the old keys and send the new one
        #
        SSHOPT="-o ConnectTimeout=3 -o StrictHostKeyChecking=no -o BatchMode=Yes"
        for NODE in $NODESLIST
        do
           #
           #    Copy de la clef generee sur le serveur pour le client sur celui-ci
           #
           #
           sudo -u  postgres ssh postgres@$NODE rm -f \
                    "~postgres/.ssh/id_rsa"
           #
           sudo -u  postgres ssh postgres@$NODE rm -f \
                    "~postgres/.ssh/id_rsa.pub"
           #
           sudo -iu postgres scp ./.ssh/$NODE\_id_rsa \
                    "postgres@$NODE:~postgres/.ssh/id_rsa"
           #
           sudo -iu postgres scp ./.ssh/$NODE\_id_rsa.pub \
                    "postgres@$NODE:~postgres/.ssh/id_rsa.pub"
        done
        #-----------------------------------------------------------------------------
        #                               rollout the new keys
        #-----------------------------------------------------------------------------
        set $NODESLIST
        NODE1="$1" ; NODE2="$2" ; NODE3="$3"
        SSHOPT="-o ConnectTimeout=3 -o StrictHostKeyChecking=no -o BatchMode=Yes"
        #
        echo "Deploiement / remplacement  des clefs SSH sur $NODE1"
        if [[ "$NODE2" != "" ]]
        then
           sudo -iu postgres ssh-copy-id -f -i ./.ssh/$NODE1\_id_rsa.pub postgres@$NODE2
           sudo -iu postgres ssh-copy-id -f -i ./.ssh/$NODE2\_id_rsa.pub postgres@$NODE1
           # Add NODE2 host key in NODE1 known_hosts and reverse
           sudo -iu postgres ssh $SSHOPT $NODE2 ssh $SSHOPT $NODE1 exit
           sudo -iu postgres ssh $SSHOPT $NODE1 ssh $SSHOPT $NODE2 exit
        fi
        if [[ "$NODE3" != "" ]]
        then
           sudo -iu postgres ssh-copy-id -f -i ./.ssh/$NODE1\_id_rsa.pub postgres@$NODE3
           sudo -iu postgres ssh-copy-id -f -i ./.ssh/$NODE2\_id_rsa.pub postgres@$NODE3
           sudo -iu postgres ssh-copy-id -f -i ./.ssh/$NODE3\_id_rsa.pub postgres@$NODE1
           sudo -iu postgres ssh-copy-id -f -i ./.ssh/$NODE3\_id_rsa.pub postgres@$NODE2
           sudo -iu postgres ssh $SSHOPT $NODE3 ssh $SSHOPT $NODE1 exit
           sudo -iu postgres ssh $SSHOPT $NODE3 ssh $SSHOPT $NODE2 exit
           sudo -iu postgres ssh $SSHOPT $NODE1 ssh $SSHOPT $NODE3 exit
           sudo -iu postgres ssh $SSHOPT $NODE2 ssh $SSHOPT $NODE3 exit
        fi
        for NODE in $NODESLIST
        do
           echo "Check availibility of SSH connection to the client $NODE"
           sudo -u postgres ssh -o ConnectTimeout=5 postgres@$NODE exit > /dev/null 2>&1
           if [[ $? -ne 0 ]]
           then
              Error "Connexion $NODE impossible"
           fi
        done
}
updateHosts () {
#------------------------------------------------------------------------------#
#       MAJ fichier /etc/hosts pour pouvoir utiliser les noms au lieu des IPS
#------------------------------------------------------------------------------#
        set "$TRACE"
        NODESLIST="$1"
        IPSLIST="$2"
        title "Mise a jour fichier /etc/hosts"
        NODESARRAY=($NODESLIST)
        IPSARRAY=($IPSLIST)
        i=-1
        if [[ "$SERVERIP" != "" ]] # Add the server IP address with "pgbackrest"
        then
           grep -q "$SERVERIP pgbackrest" /etc/hosts || \
              echo "$SERVERIP pgbackrest\
              # DO NOT REMOVE THIS IS NECESSARY FOR PGBACKREST" >> /etc/hosts
        fi
        for NODE in $NODESLIST    Adds clients nodes names and IP in /etc/hosts
        do
           ((i++))
           grep -q "${IPSARRAY[$i]} ${NODESARRAY[$i]}" /etc/hosts || \
              echo "${IPSARRAY[$i]} ${NODESARRAY[$i]} \
              # DO NOT REMOVE THIS IS NECESSARY FOR PGBACKREST" >> /etc/hosts
        done
}
getClientsIPS () {
#------------------------------------------------------------------------------#
#               Recuperation des IPS des clients PostgreSQL
#------------------------------------------------------------------------------#
        set "$TRACE"
        if [[ "$SERVERIP" = "" ]]
        then
           Error "You must provide the SERVER IP address (option -I)"
        fi
        clear
        title "Getting patroni network configuration ..."
        WORKFILE=/tmp/$$
        patronictl list > $WORKFILE
        NODESLIST=$(awk '/\|/&& $10!="TL" {print $2}' $WORKFILE)
        IPSLIST=$(awk '/\|/  && $10!="TL" {print $4}' $WORKFILE)
        SCOPE=$(awk '/+/ {print $3}' $WORKFILE)
        rm -f $WORKFILE
        updateHosts "$NODESLIST" "$IPSLIST"
}
installClient () {
#------------------------------------------------------------------------------#
#               Recuperation des IPS des clients PostgreSQL
#------------------------------------------------------------------------------#
        set "$TRACE"
        #
        if [[ "$STANZA" = "" ]]
        then
           STANZA=$(patronictl -c /etc/patroni/patronictl.yml list | \
                    awk '$2=="Cluster:" {print $3}')
        fi
        if [[ "$STANZA" = "" ]]
        then
                Error "Le STANZA/CLUSTER NAME is mendatory ('-s option'"
                Help
        fi
        getClientsIPS
        #
        title "pgbackrest installation on this client node"
        #
        echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
             > /etc/apt/sources.list.d/pgdg.list
        apt-get update
        rm -Rf /etc/pgbackrest /etc/pgbackrest.conf
        apt-get install -y pgbackrest > /dev/null
        #
        mkdir -p ~postgres/.ssh
        chown postgres:postgres ~postgres/.ssh
        chmod 750 ~postgres/.ssh
        #
        genConfFile_client
        #
        updatePatroni_auto
        #
        echo "ENDED !!!"
        echo "#-------------------------------------------------------------------"
        echo "# For the server installation you must follow the followeing process"
        echo "#"
        echo "# 1) connect yourself on the server with root or a sudo user"
        echo "#"
        echo "# 2) run the script from the directory where it's installed"
        echo "#"
        echo -e "$YELLOW"
        echo '# ./pgbackrest-install.sh -s' $SCOPE '-n "'$NODESLIST'" -i "'$IPSLIST'"'
        echo "#"
        echo '#       BE CARREFULL to enclose the nodes and IP lists between ""'
        echo -e "$DEFAULT"
        echo "#-------------------------------------------------------------------"
}
updatePatroni_auto () {
#------------------------------------------------------------------------------#
#       Mise a jour de la configuration patroni pour utilisation pgbackrest
#
#       Ceci se fait en utilisation l'API REST de patroni (Merci Zalendo! )
#------------------------------------------------------------------------------#
        set "$TRACE"
        RESTAPI=$(grep -A4 '^restapi' /etc/patroni/patroni.yml | \
                  awk '/connect_address:/ {print $2}' |tr -d ' ')
        RESTAPI=${RESTAPI:-"localhost:8008"}   # Par defaut si pas trouve !!
        #
        apt-get install -y curl > /dev/null
        #
        curl --connect-timeout 5 -s http://$RESTAPI/config | grep -q "pgbackrest"
        if [[ $? -eq 0 ]]
        then
                Msg -i "PATRONI  configuration already done : ignored"
                return
        fi
        title "PATRONI  configuration automaticaly updating..."
        #
        curl --connect-timeout 5 -s -XPATCH -d \
                '{"postgresql":{"parameters":{"archive_command":"/usr/bin/pgbackrest  \
                --stanza=prod archive-push %p"}}}' \
                http://$RESTAPI/config  > /dev/null || Error "curl RC $?"
        #
        curl --connect-timeout 5 -s -XPATCH -d \
                '{"postgresql":{"pgbackrest":{"command":"/usr/bin/pgbackrest \
                --stanza=prod --log-level-file=detail \
                --delta restore","keep_data": true,"no_params": true}}}' \
                 http://$RESTAPI/config > /dev/null || Error "curl RC $?"
        #
        curl --connect-timeout 5 -s -XPATCH -d \
                '{"postgresql":{"recovery_conf":{"restore_command":"/usr/bin/pgbackrest \
                   --stanza=prod --log-level-file=detail archive-get %f %p"}}}' \
                 http://$RESTAPI/config > /dev/null || Error "curl RC $?"
        #
        Msg -i "PATRONI/PGBACREST parameters added/modified :"
        curl --connect-timeout 5 -s http://$RESTAPI/config | jq . | grep "pgbackrest"
        patronictl reload $STANZA
}
updatePatroni_manuel () {
        set "$TRACE"
        echo "#-------------------------------------------------------------------"
        echo "# modifiez la configuration pour ajouter les lignes suivantes avec"
        echo "# patronictl edit-config"
        echo "#"
        echo "# Faites un copier/coller pour reporter ces parametres dans la"
        echo "# clause 'postgresql' de la configuration"
        echo "#-------------------------------------------------------------------"
        echo "postgresql:"
        echo -e "$YELLOW"
        echo "  parameters:"
        echo "    archive_mode: 'on'"
        echo "    archive_command: /usr/bin/pgbackrest --stanza=$STANZA archive-push %p"
        echo "  pgbackrest:"
        echo "    command: /usr/bin/pgbackrest --stanza=$STANZA --log-level-file=detail --delta restore"
        echo "    keep_data: true"
        echo "    no_params: true"
        echo "  recovery_conf:"
        echo "    restore_command: /usr/bin/pgbackrest --stanza=$STANZA archive-get %f %p"
        echo "  use_pg_rewind: true"
        echo "  use_slots: true"
        echo -e $RED
        echo "# ATTENTION DE RESPECTER L'INDENTATION ET DE NE PAS METTRE"
        echo "# DE TABULATIONS dans ce fichier !!!"
        echo -e $DEFAULT
        echo "#-------------------------------------------------------------------"
        echo "#              faites <ENTER> pour lancer patronictl edit-config"
        echo "#-------------------------------------------------------------------"
        read
        #
        export EDITOR="vi"
        patronictl edit-config
}
genConfFile_client () {
#------------------------------------------------------------------------------#
#               PGBACKREST client configuration file Generation
#------------------------------------------------------------------------------#
        set "$TRACE"
        CONFFILE=$(find /etc -name pgbackrest.conf)  # Depend de l'OS
        CONFFILE=${CONFFILE:-"/etc/pgbackrest.conf"}
        title "Generation du fichier de configuration CLIENT $CONFFILE"
        cat <<EOF> $CONFFILE
[global]
log-level-console=info
log-level-file=detail
#backup-standby=y
#archive-async=y
compress-type=none

[$STANZA]
repo1-host=$SERVERIP
repo1-host-user=postgres
pg1-path=/var/lib/postgresql/$PGVERSION/main
EOF
}
cleanInstall () {
#------------------------------------------------------------------------------#
#                   Suppress a previous installation if exist
#------------------------------------------------------------------------------#
        set "$TRACE"
        while true
        do
           title "Suppress a previous installation if exist"
           echo "Do you confirm the suppression ?"
           echo ""
           echo "Type 'yes' to confirm or hit <ENTER> for bypass"
           echo ""
           read REP
           if [[ "$REP" = "yes" ]]
           then
              break
           else
              return
           fi
        done
        apt purge -y pgbackrest
        SSHOPT="-o ConnectTimeout=3 -o StrictHostKeyChecking=no -o BatchMode=Yes"
        for NODE in $NODESLIST
        do
          # Suppress the server public SSH key on postgres user on the clients nodes
          sudo -u postgres ssh $SSHOPT postgres@$NODE \
                'sed -i /pgbackrest/d' .ssh/authorized_keys > /dev/null 2>&1
        done
        userdel -r postgres
        rm -Rf /var/lib/pgbackrest
        rm -Rf /etc/pgbackrest
        rm -Rf /var/log/pgbackrest/
        rm -Rf /tmp/pgbackrest/
}
installServer () {
#------------------------------------------------------------------------------#
#               Installation de pgbackrest sur le serveur de sauvegarde
#------------------------------------------------------------------------------#
        set "$TRACE"
        if [[ "$STANZA" = "" ]]
        then
                Error "The STANZA/CLUSTER NAME is mendatory ('-s option'"
                Help
        fi
        if [[ "$NODESLIST" = "" ]]
        then
           Error "You must provide the clients nodes names (option -n)"
        fi
        #
        if [[ "$IPSLIST" = "" ]]
        then
           Error "You must provide the clients IP adresses list (option -i)"
        fi

        #
        SERVERIP=$(hostname -I)
        NODESARRAY=($NODESLIST)
        IPSARRAY=($IPSLIST)
        echo -e "$YELLOW"
        echo "#----------------------------------------------------------------"
        echo "# You are going to install pgbackrest with the parameters below :"
        echo "#"
        echo "#          Mode : $NODETYPE"
        echo "#          IP   : $SERVERIP (Local server IP)"
        echo "#"
        echo -e "# \t NODE \t\t IP address"
        echo -e "# \t --------------- ----------------"
        i=-1
        for NODE in $NODESLIST
        do
           ((i++))
           echo -e "# \t ${NODESARRAY[$i]} \t\t ${IPSARRAY[$i]}"
        done
        echo "#----------------------------------------------------------------"
        echo "#         hit <ENTER> to continue or <CTRL-C> to cancel "
        echo "#----------------------------------------------------------------"
        echo -e "$DEFAULT"
        read
        cleanInstall
        #
        #installHaproxy
        title "pgbackrest installation from the OS package"
        #
        # Ajout repository du package DEBIAN/PGBACKREST
        wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
        echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > \
             /etc/apt/sources.list.d/pgdg.list
        apt-get update
        apt-get install -y pgbackrest
        #
        # Ajout user postgres
        title "postgres unix user creation"
        useradd -m -d /home/postgres -s /bin/bash postgres
        chmod 750 ~postgres
        echo "postgres:IjNbGt56+" | chpasswd
        sudo -iu postgres mkdir -p ~postgres/.ssh
        chmod 700 ~postgres/.ssh
        sudo -iu postgres touch known_hosts
        # adduser --disabled-password --gecos "" postgres
        # echo "backrest:BaCkReStPaSs" | chpasswd
        # useradd --system --home-dir "/var/lib/pgbackrest" --comment "pgBackRest" pgbackrest
        # echo "backrest:BaCkReStPaSs" | chpasswd
        # passwd -u pgbackrest
        #
        updateHosts "$NODESLIST" "$IPSLIST"
        #
        # Création répertoire des logs
        mkdir -p -m 770 /var/log/pgbackrest
        chown postgres:postgres /var/log/pgbackrest
        # Repository creation
        mkdir -p /var/lib/pgbackrest
        chown postgres:postgres /var/lib/pgbackrest
        chmod 750 /var/lib/pgbackrest
        # Configuration file generation
        title "Server onfiguration file Generation $CONFFILE"
        CONFFILE=$(find /etc -name pgbackrest.conf)  # Peut dependre de l'installation #
        CONFFILE=${CONFFILE:-"/etc/pgbackrest/pgbackrest.conf"}
        mkdir -p $(dirname $CONFFILE)
        cat <<EOF> $CONFFILE
[global]
process-max=5
stop-auto=y
start-fast=y
repo1-bundle=y
repo1-block=y
repo1-path=/var/lib/pgbackrest/$STANZA
repo1-retention-full=7

[global:backup]
# more cores for backup
process-max=4

[global:restore]
# all the cores for restore
process-max=8

[global:archive-push]
# more cores for archive-push
process-max=3

[global:archive-get]
# fewer cores for archive-get
process-max=3

[$STANZA]
EOF
        i=0
        for NODE in $NODESLIST # Adds a section for each node
        do
                ((i++))
echo "#
$NODE-path=/var/lib/postgresql/$PGVERSION/main
$NODE-port=5432
$NODE-host=$NODE" >> $CONFFILE
        done
        chmod 640 $CONFFILE
        chown postgres:postgres $CONFFILE
        #
        genKey_Server
        #
        title "Stanza $STANZA Creation"
        # Stanza Creation
        sudo -u postgres pgbackrest --stanza=$STANZA stanza-create || \
             Error "creation stanza RC $?"

}
#------------------------------------------------------------------------------#
#                       M       A       I       N
#------------------------------------------------------------------------------#
if [[ "$(whoami)" != "root" ]]
then
        exec sudo $0 "$@"     # Execution de ce script en tant que root #
fi
while getopts bchi:I:n:s:v:x OPT
do
   case "$OPT" in
      b) NODETYPE="server"   ;; # Installation on the backup server
      c) NODETYPE="client"   ;; # Installation on a client node (postgresql)
      h) Help                ;; # Affichage de l'entete du script
      i) IPSLIST="$OPTARG"   ;; # clients IP address list
      I) SERVERIP="$OPTARG"  ;; # Backup server IP address
      s) STANZA="$OPTARG"    ;; # Stanza name (equivalent to patroni scope name
      n) NODESLIST="$OPTARG" ;; # postgresql patroni nodes names
      v) PGVERSION="$OPTARG" ;; # Postgresql version
      x) TRACE="-x"          ;; # Activate script debugging
   esac
done
#------------------------------------------------------------------------------#
#                       Initialistion de variables
#------------------------------------------------------------------------------#
TRACE=${TRACE:-"+x"}
set "$TRACE"
PGVERSION=${PGVERSION:-"15"}
displayBanner "PGBACKREST" "installer"
#------------------------------------------------------------------------------#
case "$NODETYPE" in
   "server") installServer ;;
   "client") installClient ;;
   *)        Error "You MUST choose between '-b' (backup server) or '-c' (client)"
             ;;
esac
