#!/usr/bin/env bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
[[ -z "$CNFDIR" ]] && CNFDIR="$DIR/cnf"
. "$DIR"/cnf.sh import
set -o nounset

function usage () {
    echo "Usage :  $0 [options]
    Replication setup. Use a backup taken with dump.sh or snap.sh.

    Config dirs:
        SERVER/mysql.cnf     Slave [client]
        SERVER/master.cnf    Master [client]

    Examples:
            $0 -s SLAVE -o /backups

    Required:
        -o BACKUPDIR    Dump or snapshot dir (dump.sh -g or snap.sh)

    Options:
        -l LOGFILE      Log file name (change master)
        -p POS          Log file position (change master)
        -h|help         Display this message
    "
}

OUTDIR=
SERVER=
LABEL=
MASTER_LOG_FILE=
MASTER_LOG_POS=
while getopts ":s:l:p:o:hv" opt
do
  case $opt in
      s) LABEL=$OPTARG;;
      l) MASTER_LOG_FILE=$OPTARG;;
      p) MASTER_LOG_POS=$OPTARG;;
      o) OUTDIR=$OPTARG ;;
      h|help     )  usage; exit 0   ;;
      * )  echo -e "\n  Option does not exist : $OPTARG\n"
          usage; exit 1   ;;
  esac
done
shift $(($OPTIND-1))
OTHERARGS=$@

if [ -z "$LABEL" ]; then
    echo ":: Which config you want to use? (use -s option)"
    exit 2
fi

# access config files
SERVER=$(MyCnf "$LABEL" mysql)
[[ -z "$SERVER" ]] && echo ":: No config for $LABEL" && exit 1
MASTER=$(MyCnf "$LABEL" master)
[[ -z "$MASTER" ]] && echo ":: No master config for $LABEL" && exit 1

OUTDIR=$(readlink -f "$OUTDIR")
if [ -z "$MASTER_LOG_FILE" ] || [ -z "$MASTER_LOG_POS" ]; then
    if [ -f "$OUTDIR"/snap/xtrabackup_binlog_info ]; then
        echo ":: Reading master position from snapshot"
        MASTER_LOG_FILE=$(awk '{print $1}' "$OUTDIR"/snap/xtrabackup_binlog_info)
        MASTER_LOG_POS=$(awk '{print $2}' "$OUTDIR"/snap/xtrabackup_binlog_info)
    elif [ -f "$OUTDIR"/ALL_USER_DB.sql.gz ]; then
        echo ":: Reading master position from dump"
        MASTER_LOG_FILE=$(zcat "$OUTDIR"/ALL_USER_DB.sql.gz | head -n 100 | egrep '^--\s*CHANGE' | sed 's/^--\s*//' | awk -F'=' '{print $2}' | awk -F, '{print $1}' | sed "s/'//g")
        MASTER_LOG_POS=$(zcat "$OUTDIR"/ALL_USER_DB.sql.gz | head -n 100 | egrep '^--\s*CHANGE' | sed 's/^--\s*//' | awk -F'=' '{print $3}' | sed 's/;//' | sed 's/ //g')
    else
        echo ":: Master postion was not supplied (-m and -l). Couldn't find position files in the backup dir"
        exit 2
    fi
fi

if [ -z "$MASTER_LOG_FILE" ] || [ -z "$MASTER_LOG_POS" ]; then
    echo ":: Failed to parse master log file and position. Try checking backupdir or use -m and -l"
    exit 2
fi


master_hostname=$(mysql --defaults-file="$MASTER" -ANe"SELECT @@hostname;")
master_port=$(mysql --defaults-file="$MASTER" -ANe"SELECT @@port;")
master_id=$(mysql --defaults-file="$MASTER" -ANe"SELECT @@server_id;")

slave_hostname=$(mysql --defaults-file="$SERVER" -ANe"SELECT @@hostname;")
slave_port=$(mysql --defaults-file="$SERVER" -ANe"SELECT @@port;")
slave_id=$(mysql --defaults-file="$SERVER" -ANe"SELECT @@server_id;")

slave_user="replication_slave_${LABEL}_${slave_hostname}_${slave_port}"
slave_pass=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)

if [ "$slave_id" -eq "$master_id" ]; then
    echo ":: Slave server_id cannot be the same as the master's (server_id: $master_id)"
    exit 2
fi

echo ":: Replication setup"
echo ''
echo "   master server   : ${master_hostname}:${master_port}"
echo "   master position : ${MASTER_LOG_FILE}:${MASTER_LOG_POS}"
echo "   slave server    : ${slave_hostname}:${slave_port}"
echo "   slave repl user : $slave_user"
echo "   slave repl pass : $slave_pass"
read -p ":: Continue? (y/n)" -n 1 -r
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo ":: Bye"
    exit 2
fi

mysql --defaults-file="$MASTER" -ANe"drop user '$slave_user'@'%';" >/dev/null 2>&1
mysql --defaults-file="$MASTER" -ANe"create user '$slave_user'@'%' identified by '$slave_pass';"
mysql --defaults-file="$MASTER" -ANe"grant replication slave on *.* to '$slave_user'@'%'; flush privileges;"
if [ $? -ne 0 ]; then
    echo ":: Error creating replication user on master server"
    exit $?
fi


sql="
STOP SLAVE;
change master to 
    master_host='$master_hostname', 
    master_port=$master_port, 
    master_user='$slave_user', 
    master_password='$slave_pass',
    master_log_file='$MASTER_LOG_FILE',
    master_log_pos=$MASTER_LOG_POS;
START SLAVE;
"

echo ":: Setting up replication with:"
echo "$sql"
mysql --defaults-file="$SERVER" -ANe"$sql"

sleep 5

mysql --defaults-file="$SERVER" -e'SHOW SLAVE STATUS\G'



