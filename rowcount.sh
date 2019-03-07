#!/usr/bin/env bash
# a quick rowcount


DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
[[ -z "$CNFDIR" ]] && CNFDIR="$DIR/cnf"
. "$DIR"/cnf.sh import
set -o nounset

function usage () {
    echo "Usage :  $0 [options] 
    rowcounter

    Examples:
        $0 -s default -- <OTHER mysqltuner.pl OPTIONS>

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
SERVER=$(MyCnf "$LABEL" mysql)
[[ -z "$SERVER" ]] && echo ":: No config for $LABEL" && exit 1


mysql --defaults-file="$SERVER" -t -e "
select @@hostname as HOSTNAME, @@port as PORT;

select COUNT(*) AS DB_COUNT from information_schema.SCHEMATA;

select COUNT(*) AS U_DB_COUNT from information_schema.SCHEMATA
where SCHEMA_NAME not in ('mysql', 'information_schema', 'performance_schema', 'sys');

select COUNT(*) as U_EVENT_COUNT
from information_schema.EVENTS
where EVENT_CATALOG not in ('mysql', 'information_schema', 'performance_schema', 'sys');

select count(*) AS U_PROC_FUN_COUNT
from information_schema.schemata S
inner join mysql.proc P on P.db = S.SCHEMA_NAME
where S.SCHEMA_NAME not in ('mysql', 'information_schema', 'performance_schema', 'sys');

select S.SCHEMA_NAME,count(*) AS U_PROC_FUN_COUNT
from information_schema.schemata S
inner join mysql.proc P on P.db = S.SCHEMA_NAME
where S.SCHEMA_NAME not in ('mysql', 'information_schema', 'performance_schema', 'sys')
GROUP BY 1 ;

select TABLE_SCHEMA as DB,
count( case when T.TABLE_TYPE = 'BASE TABLE' then 1 else NULL end ) as U_TABLE_COUNT,
count( case when T.TABLE_TYPE = 'VIEW' then 1 else NULL end ) as U_VIEW_COUNT
from information_schema.tables T
where T.TABLE_SCHEMA not in ('mysql', 'information_schema', 'performance_schema', 'sys')
group by 1
order by 1;

"
