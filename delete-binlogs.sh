#!/usr/bin/env bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
[[ -z "$CNFDIR" ]] && CNFDIR="$DIR/cnf"
. "$DIR"/cnf.sh import
set -o nounset

function usage () {
    echo "Usage :  $0 [options] 
    Delete old binary logs

    Examples:
        $0 -s SQL1 -k 48

    Required:
        -s SERVER    Config name

    Options:
        -k HOURS    How many hours of binary logs to keep (default: 24)
        -c          Check for slave running first
        -h|help     Display this message
    "
}

SERVER=
LABEL=
SW_c=
KEEP_HOURS=24
while getopts ":s:k:ch" opt
do
  case $opt in
      s) LABEL=$OPTARG;;
      c) SW_c=1;;
      k) KEEP_HOURS=$OPTARG;;
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
SERVER=$(MyCnf "$LABEL" mysql)
[[ -z "$SERVER" ]] && echo ":: No config for $LABEL" && exit 1

if [ -n "$SW_c" ]; then

    SLAVE=$(MyCnf "$LABEL" slave)
    [[ -z "$SLAVE" ]] && echo ":: No config for $LABEL" && exit 1

    # check slave status
    slave_ok=$(mysql --defaults-file="$SLAVE" -ANe"SELECT variable_value FROM information_schema.global_status WHERE variable_name='SLAVE_RUNNING';" | \
    grep -i 'on' | wc -l)

    if [ "$slave_ok" -ne 1 ]; then
        echo ":: Slave doesn't check out. I won't do anything"
        exit 1
    fi
fi

date_before=$(mysql --defaults-file="$SERVER" -ANe"select date_sub(now(), interval ${KEEP_HOURS} hour)\G" | tail -n 1)
if [ -z "$date_before" ]; then
    echo ":: Got invalid date. Something went wrong"
    exit 1
fi
echo ":: Delete binlogs older than $date_before"
mysql --defaults-file="$SERVER" -ANe"PURGE BINARY LOGS BEFORE '${date_before}'\G"


