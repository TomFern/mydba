#!/usr/bin/env bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export PATH="$DIR":$PATH
[[ -z "$CNFDIR" ]] && CNFDIR="$DIR/cnf"
. "$DIR"/cnf.sh import
set -o nounset

function usage () {
    echo "Usage :  $0 [options] -- [OTHER OPTIONS FOR pt-table-sync]
    Copy tables with pt-table-sync

    Examples:
        $0 -s SQL1 -g SQL2 -t DB1.MyTable -r DB2.MyCopyTable

    Required:
        -s SERVER        Config for source server
        -g SERVER        Config for destination server
        -t DB.ORIGINAL  Original/master table as DATABASE.TABLE
        -r DB.COPY      COPY table as DATABASE.TABLE

    Options:
        -h|help     Display this message
    "
}

SERVER=
TNAME=
ORIGINAL=
COPY=
LABEL=
while getopts ":s:t:g:r:hv" opt
do
  case $opt in
      s)  LABEL=$OPTARG
          ;;
      g) TNAME=$OPTARG;;
      t) ORIGINAL=$OPTARG;;
      r) COPY=$OPTARG;;
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

if [ -z "$TNAME" ]; then
    echo ":: Which config you want to use? (use -g option)"
    exit 2
fi

SERVER=$(MyCnf "$LABEL" mysql)
[[ -z "$SERVER" ]] && echo ":: No config for $LABEL" && exit 1
DEST=$(MyCnf "$TNAME" mysql)
[[ -z "$DEST" ]] && echo ":: No config for $TNAME" && exit 1

ORIGINAL_DB=$(echo "$ORIGINAL" | awk -F. '{print $1}')
ORIGINAL_TABLE=$(echo "$ORIGINAL" | awk -F. '{print $2}')
COPY_DB=$(echo "$COPY" | awk -F. '{print $1}')
COPY_TABLE=$(echo "$COPY" | awk -F. '{print $2}')

# check other parameters
if [ -z "$ORIGINAL" ] || [ -z "$COPY" ] || \
   [ -z "$ORIGINAL_DB" ] || [ -z "$COPY_DB" ] || \
   [ -z "$ORIGINAL_TABLE" ] || [ -z "$COPY_TABLE" ]; then
      echo ":: Need you to supply -t and -r with DB.TABLE format"
      exit 2
fi

dsn_source="$(DSN "$LABEL"),D=$ORIGINAL_DB,t=$ORIGINAL_TABLE"
[[ -z "$dsn_source" ]] && echo ":: Failed to create DSN for $LABEL" && exit 1
dsn_dest="$(DSN "$TNAME"),D=$COPY_DB,t=$COPY_TABLE"
[[ -z "$dsn_dest" ]] && echo ":: Failed to create DSN for $TNAME" && exit 1

echo ":: Doing a dry-run"
pt-table-sync "$dsn_source" "$dsn_dest" --dry-run --verbose
if [ $? -eq 0 ]; then
    echo ":: Doing a print"
    pt-table-sync "$dsn_source" "$dsn_dest" --dry-run --verbose $OTHERARGS
fi
if [ $? -eq 0 ]; then
    echo ":: Command to run is:"
    echo pt-table-sync "$dsn_source" "$dsn_dest" --execute $OTHERARGS
    read -p ":: Execute? (y/n)" -n 1 -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo ":: Bye"
        exit 2
    fi
    echo ""
    pt-table-sync "$dsn_source" "$dsn_dest" --execute $OTHERARGS
fi

