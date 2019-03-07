#!/usr/bin/env bash
# cycle error log

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
[[ -z "$CNFDIR" ]] && CNFDIR="$DIR/cnf"
. "$DIR"/cnf.sh import
set -o nounset

function usage () {
    echo "Usage :  $0 [options] 
    Cycle MySQL Logs

    Examples:
        $0 -s SQL1

    Required:
        -s SERVER    Config name

    Options:
        -h|help     Display this message
    "
}

SERVER=
LABEL=
while getopts ":s:h" opt
do
  case $opt in
      s) LABEL=$OPTARG;;
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
SERVER=$(MyServer "$LABEL")
[[ -z "$SERVER" ]] && echo ":: No config for $LABEL" && exit 1

mysql --defaults-file=$(MyCnf "$LABEL" mysql) -ANe'FLUSH ERROR LOGS; FLUSH SLOW LOGS;'

