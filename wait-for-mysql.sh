#!/usr/bin/env bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export PATH="$DIR":$PATH
[[ -z "$CNFDIR" ]] && CNFDIR="$DIR/cnf"
. "$DIR"/cnf.sh import
set -o nounset

function usage () {
    echo "Usage :  $0 [options]
    Wait for mysql connection

    Examples:
        $0 -s SQL1

    Required:
        -s SERVER        Config for source server

    Options:
        -h|help     Display this message
    "
}

LABEL=
while getopts ":s:hv" opt
do
  case $opt in
      s)  LABEL=$OPTARG ;;
      h|help     )  usage; exit 0   ;;
      * )  echo -e "\n  Option does not exist : $OPTARG\n"
          usage; exit 1   ;;
  esac
done
shift $(($OPTIND-1))
OTHERARGS=$@

if [ -z "$LABEL" ]; then
    echo ":: Which config you want to use? (use -s option)" >&2
    exit 2
fi

# access config files
SERVER=$(MyCnf "$LABEL" mysql)
[[ -z "$SERVER" ]] && echo ":: No config for $LABEL" && exit 1


function try_mysql {
    mysql --defaults-file="$SERVER" -ANe"SELECT @@PORT;" >/dev/null 2>&1
    echo "$?"
}

while [ $(try_mysql) -ne 0 ]; do
    sleep 0.1
done
    
