#!/usr/bin/env bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
[[ -z "$CNFDIR" ]] && CNFDIR="$DIR/cnf"
. "$DIR"/cnf.sh import
set -o nounset

function usage () {
    echo "Usage :  $0 [options] 
    Export users & grants (except for root)

    Required:
        -s SERVER   Config name
    "
}

LABEL=
while getopts ":o:s:Zhv" opt
do
  case $opt in
      s) LABEL=$OPTARG
          ;;
      h)  usage; exit 0   ;;
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

STMT="SELECT CONCAT('SHOW GRANTS FOR ''',user,'''@''',host,''';') FROM mysql.user WHERE user<>'' and user <> 'root';"
 mysql --defaults-file="$SERVER" -ANe"$STMT" | while read sql; do
     echo "-- $sql"
     mysql --defaults-file="$SERVER" -ANe"$sql" | sed 's/$/;/'
done
