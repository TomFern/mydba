#!/usr/bin/env bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
[[ -z "$CNFDIR" ]] && CNFDIR="$DIR/cnf"
. "$DIR"/cnf.sh import
set -o nounset

function usage () {
    echo "Usage :  $0 [options]
    Replication heartbeat monitor

    Examples:

        Start update daemon
            $0 -s SQL1 -d
        
        Run replication monitor on foreground
            $0 -s SQL1 -m
        
        Autostart slave if delay is greater than 10 seconds
            $0 -s SQL1 -a 10 -l 60

    Required:
        -s SERVER    Config name

    Options:
        -i ID       Master server id default=1
        -d          Start update daemon and create heartbeat table if required
        -m          Run monitor on foreground (no alerts)
        -l SECONDS  Threshold for alert (default=-1)
        -a SECONDS  Threshold for start slave (can be floating point, 0 to disable) default=0
    "
}

PID_FN=/tmp/mysql-pt-heartbeat.pid
SERVER=
SW_m=
SW_d=
THRESHOLD=-1
AUTO_START=10
EMAILS=
while getopts ":s:l:e:a:mdhv" opt
do
  case $opt in
      # a) AUTO_START=$OPTARG;;
      s) LABEL=$OPTARG ;;
      d) SW_d=1;;
      m) SW_m=1;;
      l) THRESHOLD=$OPTARG;;
      h|help     )  usage; exit 0   ;;
      * )  echo -e "\n  Option does not exist : $OPTARG\n"
          usage; exit 1   ;;
  esac
done
shift $(($OPTIND-1))
OTHERARGS=$@

if ! which pt-heartbeat >/dev/null 2>&1; then
    echo ":: pt-heartbeat not found in path, you must keep working"
    exit 3
fi

if [ -z "$LABEL" ]; then
    echo ":: Which config you want to use? (use -s option)"
    exit 2
fi

SERVER=$(MyCnf "$LABEL" mysql)
SLAVE=$(MyCnf "$LABEL" slave)
[[ -z "$SERVER" ]] && echo ":: No config for $LABEL" && exit 1
[[ -z "$SLAVE" ]] && echo ":: Slave not set for $LABEL" && exit 1

function check_updater {
    if [ ! -f "$PID_FN" ]; then
        echo 0
        return
    else
        pid=$(cat "$PID_FN")
        if ! kill -0 $pid 2>/dev/null ; then
            rm -f "$PID_FN"
            echo 0
            return
        fi
    fi
    echo 1
}

function start_updater {
    echo ":: Start heartbeat update daemon"
    username=$(awk -F '=' '/user/ {print $2}' "$SERVER" | head -n 1 | tr -d ' ')
    password=$(awk -F '=' '/password/ {print $2}' "$SERVER" | head -n 1 | tr -d ' ')
    port=$(awk -F '=' '/port/ {print $2}' "$SERVER" | head -n 1 | tr -d ' ')
    host=$(awk -F '=' '/host/ {print $2}' "$SERVER" | head -n 1 | tr -d ' ')
    sock=$(awk -F '=' '/socket/ {print $2}' "$SERVER" | head -n 1 | tr -d ' ')
    link="--host $host --port $port"
    if [ -n "$sock" ]; then
        link="--socket $sock"
    fi

    pt-heartbeat --daemonize --pid "$PID_FN" \
        --create-table --database mysql \
        $link \
        -user $username --password "$password" \
        --update --utc
}

if [ -n "$SW_d" ]; then
    # start updater if required
    if [ $(check_updater) -eq 0 ]; then
        start_updater
        sleep 2
        echo ':: TIP: you can create an event (if event scheduler is enabled) and avoid running the updater

use mysql;
delimiter $$
CREATE EVENT heartbeat 
ON SCHEDULE EVERY 1 SECOND 
DO
BEGIN
    INSERT INTO mysql.heartbeat (server_id, ts) VALUES (@@server_id, UTC_TIMESTAMP()) ON DUPLICATE KEY UPDATE ts=UTC_TIMESTAMP();
END
$$
delimiter ;

'

    fi
    if [ $(check_updater) -eq 0 ]; then
        echo ":: WARNING: failed to start pt-heartbeat updater"
    fi
fi

# get master server id
master_server_id=$(mysql --defaults-file="$SERVER" -ANe"SELECT @@server_id;")
slave_server_id=$(mysql --defaults-file="$SLAVE" -ANe"SELECT @@server_id;")


# values for slave
username=$(awk -F '=' '/user/ {print $2}' "$SLAVE" | head -n 1 | tr -d ' ')
password=$(awk -F '=' '/password/ {print $2}' "$SLAVE" | head -n 1 | tr -d ' ')
port=$(awk -F '=' '/port/ {print $2}' "$SLAVE" | head -n 1 | tr -d ' ')
host=$(awk -F '=' '/host/ {print $2}' "$SLAVE" | head -n 1 | tr -d ' ')
sock=$(awk -F '=' '/socket/ {print $2}' "$SLAVE" | head -n 1 | tr -d ' ')
link="--host $host --port $port"
if [ -n "$sock" ]; then
    link="--socket $sock"
fi

if [ -n "$SW_m" ]; then
    pt-heartbeat --database mysql $link --user $username --password "$password" --monitor --master-server-id "$master_server_id" --utc
else
    delay=$(pt-heartbeat --database mysql $link --user $username --password "$password" --check --master-server-id "$master_server_id" --utc)
    st=$?

    if [ "$AUTO_START" -gt 0 ]; then
        if [ $(echo "$delay > $AUTO_START" | bc -l) -eq 1 ] && [ $(echo "$delay < $THRESHOLD" | bc -l) -eq 1 ] ; then
            mysql --defaults-file="$SERVER" -ANe"START SLAVE;" >/dev/null 2>&1
        fi
    fi

    if [ $(echo "$delay > $THRESHOLD" | bc -l) -eq 1 ]; then
        echo "Replication delay: ID${master_server_id}->ID${slave_server_id} = ${delay}s"
    fi
fi
