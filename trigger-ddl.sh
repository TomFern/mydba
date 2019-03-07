#!/usr/bin/env bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
[[ -z "$CNFDIR" ]] && CNFDIR="$DIR/cnf"
. "$DIR"/cnf.sh import
set -o nounset

function usage () {
    echo "Usage :  $0 [options]
    Generate INSERT/UPDATE/DELETE triggers to keep a local replica table.

    Config files:
        ./SERVER/mysql.cnf     --> [client] server to dump

    Examples:
        $0 -s SQL1 -t DB1.MyTable -r DB2.MyCopyTable > triggers.sql

    Required:
        -s SERVER        Config
        -t DB.ORIGINAL  Original/master table as DATABASE.TABLE
        -r DB.REPLICA   Replica table as DATABASE.TABLE

    Options:
        -h|help     Display this message
    "
}

SERVER=
LABEL=
ORIGINAL=
REPLICA=
while getopts ":s:t:r:hv" opt
do
  case $opt in
      s)  LABEL=$OPTARG
          ;;
      t) ORIGINAL=$OPTARG;;
      r) REPLICA=$OPTARG;;
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

if [ -z "$LABEL" ]; then
    echo ":: Which config you want to use? (use -s option)"
    exit 2
fi
SERVER=$(MyCnf "$LABEL" mysql)
# SERVER="$SERVER"
# [[ -z "$SERVER" ]] && echo ":: No config for $LABEL" && exit 1

ORIGINAL_DB=$(echo "$ORIGINAL" | awk -F. '{print $1}')
ORIGINAL_TABLE=$(echo "$ORIGINAL" | awk -F. '{print $2}')
REPLICA_DB=$(echo "$REPLICA" | awk -F. '{print $1}')
REPLICA_TABLE=$(echo "$REPLICA" | awk -F. '{print $2}')

# check other parameters
if [ -z "$ORIGINAL" ] || [ -z "$REPLICA" ] || \
   [ -z "$ORIGINAL_DB" ] || [ -z "$REPLICA_DB" ] || \
   [ -z "$ORIGINAL_TABLE" ] || [ -z "$REPLICA_TABLE" ]; then
      echo ":: Need you to supply -t and -r with DB.TABLE format"
      exit 2
fi


# insert triggers
gen='
use `'$ORIGINAL_DB'`;
DROP TRIGGER IF EXISTS `'$ORIGINAL_DB'`.`'${ORIGINAL_TABLE}_AFTER_INSERT'`;
delimiter |
CREATE TRIGGER `'$ORIGINAL_DB'`.`'${ORIGINAL_TABLE}'_AFTER_INSERT` 
AFTER INSERT ON `'$ORIGINAL_TABLE'` FOR EACH ROW
BEGIN

REPLACE INTO `'$REPLICA_DB'`.`'$REPLICA_TABLE'` 
('

sqlcmd="select COLUMN_NAME from information_schema.COLUMNS where TABLE_SCHEMA = '$ORIGINAL_DB' and TABLE_NAME = '$ORIGINAL_TABLE';"
colcnt=0
while read colname; do
    if [ $colcnt -ne 0 ]; then
        gen=$gen','
    fi
    gen=$gen' `'$colname'`'
    colcnt=$(($colcnt+1))
done < <(mysql --defaults-file="$SERVER" -ANe"$sqlcmd")

if [ $colcnt -eq 0 ]; then
    echo ":: ERROR no columns found on ${ORIGINAL_DB}.${ORIGINAL_TABLE}"
    exit 3
fi

gen=$gen') 
VALUES 
('

sqlcmd="select COLUMN_NAME from information_schema.COLUMNS where TABLE_SCHEMA = '$ORIGINAL_DB' and TABLE_NAME = '$ORIGINAL_TABLE';"
colcnt=0
while read colname; do
    if [ $colcnt -ne 0 ]; then
        gen=$gen','
    fi
    gen=$gen' NEW.`'$colname'`'
    colcnt=$(($colcnt+1))
done < <(mysql --defaults-file="$SERVER" -ANe"$sqlcmd")

gen=$gen')
;

END|
delimiter ;
'

echo "-- AFTER INSERT ${ORIGINAL_DB}.${ORIGINAL_TABLE}"
echo "$gen"

# update triggers
gen='
use `'$ORIGINAL_DB'`;
DROP TRIGGER IF EXISTS `'$ORIGINAL_DB'`.`'${ORIGINAL_TABLE}_AFTER_UPDATE'`;
delimiter |
CREATE TRIGGER `'$ORIGINAL_DB'`.`'${ORIGINAL_TABLE}'_AFTER_UPDATE` 
AFTER UPDATE ON `'$ORIGINAL_TABLE'` FOR EACH ROW
BEGIN

UPDATE IGNORE `'$REPLICA_DB'`.`'$REPLICA_TABLE'` SET'

sqlcmd="select COLUMN_NAME from information_schema.COLUMNS where TABLE_SCHEMA = '$ORIGINAL_DB' and TABLE_NAME = '$ORIGINAL_TABLE';"
colcnt=0
while read colname; do
    if [ $colcnt -ne 0 ]; then
        gen=$gen','
    fi
    gen=$gen'
        `'$colname'` = NEW.`'${colname}'`'
    colcnt=$(($colcnt+1))
done < <(mysql --defaults-file="$SERVER" -ANe"$sqlcmd")

gen=$gen'
WHERE '

sqlcmd="select COLUMN_NAME from information_schema.COLUMNS where TABLE_SCHEMA = '$ORIGINAL_DB' and TABLE_NAME = '$ORIGINAL_TABLE' and COLUMN_KEY = 'PRI';"
pricnt=0
while read colname; do
    if [ $pricnt -ne 0 ]; then
        gen=$gen' AND '
    fi
    gen=$gen'
        `'$colname'` = OLD.`'${colname}'`'
    pricnt=$(($pricnt+1))
done < <(mysql --defaults-file="$SERVER" -ANe"$sqlcmd")


if [ $pricnt -eq 0 ]; then
    echo ":: ERROR table has no primary keys ${ORIGINAL_DB}.${ORIGINAL_TABLE}"
    exit 3
fi

gen=$gen'
;

END|
delimiter ;
'

echo "-- AFTER UPDATE ${ORIGINAL_DB}.${ORIGINAL_TABLE}"
echo "$gen"




# delete triggers

gen='
use `'$ORIGINAL_DB'`;
DROP TRIGGER IF EXISTS `'$ORIGINAL_DB'`.`'${ORIGINAL_TABLE}_AFTER_DELETE'`;
delimiter |
CREATE TRIGGER `'$ORIGINAL_DB'`.`'${ORIGINAL_TABLE}'_AFTER_DELETE` 
AFTER DELETE ON `'$ORIGINAL_TABLE'` FOR EACH ROW
BEGIN

DELETE IGNORE FROM `'$REPLICA_DB'`.`'$REPLICA_TABLE'`
WHERE '

sqlcmd="select COLUMN_NAME from information_schema.COLUMNS where TABLE_SCHEMA = '$ORIGINAL_DB' and TABLE_NAME = '$ORIGINAL_TABLE' and COLUMN_KEY = 'PRI';"
pricnt=0
while read colname; do
    if [ $pricnt -ne 0 ]; then
        gen=$gen' AND '
    fi
    gen=$gen'
        `'$colname'` = OLD.`'${colname}'`'
    pricnt=$(($pricnt+1))
done < <(mysql --defaults-file="$SERVER" -ANe"$sqlcmd")

gen=$gen'
;

END|
delimiter ;
'

echo "-- AFTER DELETE ${ORIGINAL_DB}.${ORIGINAL_TABLE}"
echo "$gen"
