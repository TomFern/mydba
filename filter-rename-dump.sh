#!/usr/bin/env bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# PATH=$PATH:$DIR
[[ -z "$CNFDIR" ]] && CNFDIR="$DIR/cnf"
. "$DIR"/cnf.sh import
set -o nounset

function usage () {
    echo "Usage :  $0 [options] 
    Filter to rename db from mysqldump (only tested with EMPTY/NO-DATA dumps!)

    Notes:
      You probably want to load.sh with -U mode (upgrade)

    Examples:
        Create renamed dump and load it
            dump.sh -s ORIGINAL_SERVER -d ORIGINAL_DB -o /tmp
            zcat /tmp/ORIGINAL_DB.sql.gz | $0 -d ORIGINAL_DB -c NEW_DB | gzip > /tmp/NEW_DB.sql.gz
            load.sh -s NEW_SERVER -f /tmp/NEW_DB.sql -U -N -d NEW_DB

        Only for the bold:
            zcat /tmp/ORIGINAL_DB.sql.gz | $0 -d ORIGINAL_DB -c NEW_DB | load.sh -s NEW_SERVER -U -N -d NEW_DB

    Required:
        -d NAME     Original DB name
        -c NAME     New DB name

    Options:
        -h|help     Display this message
    "
}

ORIGINAL_DB=
NEW_DB=
date=$(date +"%Y%m%d-%H%M%S")
while getopts ":d:c:h" opt
do
  case $opt in
      c) NEW_DB=$OPTARG ;;
      d) ORIGINAL_DB=$OPTARG ;;
      h|help     )  usage; exit 0   ;;
      * )  echo -e "\n  Option does not exist : $OPTARG\n"
          usage; exit 1   ;;
  esac
done
shift $(($OPTIND-1))
OTHERARGS=$@

if [ -z "$ORIGINAL_DB" ]; then
    echo ":: Options -c and -d are mandatory" >&2
    exit 3
fi

cat | \
    sed 's/`'$ORIGINAL_DB'`/'$ORIGINAL_DB'/g' | \
    sed 's/'$ORIGINAL_DB'\./'$NEW_DB'./g' | \
    sed 's;'$ORIGINAL_DB'/;'$NEW_DB'/;g' | \
    sed '/^DROP TABLE/d' |  \
    sed '/\/*!50003 DROP FUNCTION/d ' | \
    sed '/\/*!50003 DROP PROCEDURE/d ' \
