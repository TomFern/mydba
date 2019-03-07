#!/usr/bin/env bash
# fk advisor

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
[[ -z "$CNFDIR" ]] && CNFDIR="$DIR/cnf"
. "$DIR"/cnf.sh import
set -o nounset

function usage () {
    echo "Usage :  $0 [options]
    Advise on Foreign Key creation

    Config files:
        ./SERVER/mysql.cnf     --> [client] for server

   Examples:
        $0 -s SQL1 -t MyDB.MyParent -r MyChild -c \"ID NAME SURNAME\"

    Required:
        -s SERVER        Config name
        -t DB.TABLE     Parent DB and Table
        -r DB.TABLE     Referenced DB and Table
        -c \"tCOL1=rCOL1 tCOL2=rCOL2\"    Foreign Key column mapping


    Options:
        -h|help       Display this message
    "
}

# colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

SERVER=
LABEL=
O_t=
O_r=
O_c=
while getopts ":s:t:r:c:hv" opt
do
  case $opt in
    s) LABEL=$OPTARG;;
    t) O_t=$OPTARG;;
    r) O_r=$OPTARG;;
    c) O_c=$OPTARG;;
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

if [ -z "$O_t " ] || [ -z "$O_r" ] || [ -z "$O_c" ]; then
    echo ":: Options -t -r and -c are mandatory" >&2
    exit 2
fi


# access config files
SERVER=$(MyCnf "$LABEL" mysql)
[[ -z "$SERVER" ]] && echo ":: No config for $LABEL" && exit 1

# parse options
PARENT_DB=$(echo "$O_t" | awk -F. '{print $1}')
PARENT_TABLE=$(echo "$O_t" | awk -F. '{print $2}')
CHILD_DB=$(echo "$O_r" | awk -F. '{print $1}')
CHILD_TABLE=$(echo "$O_r" | awk -F. '{print $2}')

if [ -z "$CHILD_TABLE" ]; then
    CHILD_TABLE=$CHILD_DB
    CHILD_DB=$PARENT_DB
fi

PARENT_COLS=
CHILD_COLS=
while read pair; do
    if [ -n "$pair" ]; then
        parent_c=$(echo "$pair" | awk -F= '{print $1}')
        child_c=$(echo "$pair" | awk -F= '{print $2}')
        if [ -z "$child_c" ]; then 
            child_c=$parent_c
        fi
        PARENT_COLS=$PARENT_COLS" "$parent_c
        CHILD_COLS=$CHILD_COLS" "$child_c
    fi
done < <(echo "$O_c" | sed 's/ /\n/g')

# echo PARENT
# echo $PARENT_DB
# echo $PARENT_TABLE
# echo $PARENT_COLS
# echo CHILD
# echo $CHILD_DB
# echo $CHILD_TABLE
# echo $CHILD_COLS

# check charset/collation
sqlcmd="SELECT TABLE_COLLATION FROM information_schema.TABLES WHERE TABLE_NAME = '"$PARENT_TABLE"' AND TABLE_SCHEMA = '"$PARENT_DB"';"
parent_collation=$(mysql --defaults-file="$SERVER" -ANe"$sqlcmd")
sqlcmd="SELECT TABLE_COLLATION FROM information_schema.TABLES WHERE TABLE_NAME = '"$CHILD_TABLE"' AND TABLE_SCHEMA = '"$CHILD_DB"';"
child_collation=$(mysql --defaults-file="$SERVER" -ANe"$sqlcmd")
if [ "$parent_collation" != "$child_collation" ]; then
    printf ":: Table collation doesn't match ($parent_collation != $child_collation)  ${RED}BAD${NC}\n"
else
    printf ":: Table collation matches ($parent_collation)  ${GREEN}GOOD${NC}\n"
fi

# check column datatype
i=-1
while read parent_c; do
    i=$(($i + 1))
    if [ -n "$parent_c" ]; then

        sqlcmd="select COLUMN_TYPE from information_schema.COLUMNS where TABLE_SCHEMA = '"$PARENT_DB"' and TABLE_NAME = '"$PARENT_TABLE"' and COLUMN_NAME = '"$parent_c"';"
        parent_c_type=$(mysql --defaults-file="$SERVER" -ANe"$sqlcmd")

        child_c=$(echo "$CHILD_COLS" | awk '{print $'$i'}')
        sqlcmd="select COLUMN_TYPE from information_schema.COLUMNS where TABLE_SCHEMA = '"$CHILD_DB"' and TABLE_NAME = '"$CHILD_TABLE"' and COLUMN_NAME = '"$child_c"';"
        child_c_type=$(mysql --defaults-file="$SERVER" -ANe"$sqlcmd")

        if [ -z "$parent_c_type" ] || [ -z "$child_c_type" ]; then
            printf ":: Can't check datatypes for columns $parent_c -> $child_c  ${RED}BAD${NC}\n"
        elif [ "$parent_c_type" != "$child_c_type" ]; then
            printf ":: Column datatype doesn't match $parent_c -> $child_c ($parent_c_type != $child_c_type)  ${RED}BAD${NC}\n"
        else
            printf ":: Column datatype matches $parent_c -> $child_c ($parent_c_type)  ${GREEN}GOOD${NC}\n"
        fi
    fi
done < <(echo "$PARENT_COLS" | sed 's/ /\n/g')

# check for infringing rows
sqlcmd='SELECT COUNT(*) FROM `'$PARENT_DB'`.`'$PARENT_TABLE'` P
LEFT JOIN `'$CHILD_DB'`.`'$CHILD_TABLE'` C '

i=-1
join_on=
where=
parent_array=
child_array=
while read parent_c; do
    i=$(($i + 1))
    if [ -n "$parent_c" ]; then
        if [ -n "$join_on" ]; then
            join_on=$join_on' AND '
        fi
        if [ -n "$where" ]; then
            where=$where' OR '
        fi
        if [ -n "$parent_array" ]; then
            parent_array=$parent_array', '
            child_array=$child_array', '
        fi
        child_c=$(echo "$CHILD_COLS" | awk '{print $'$i'}')
        join_on=$join_on' P.`'$parent_c'`=C.`'$child_c'` '
        where=$where' C.`'$child_c'` IS NULL '
        parent_array=$parent_array'`'$parent_c'`'
        child_array=$child_array'`'$child_c'`'
    fi
done < <(echo "$PARENT_COLS" | sed 's/ /\n/g')

sqlcmd=$sqlcmd'
ON
    '$join_on'
WHERE
    '$where'
;
'

rowcount=$(mysql --defaults-file="$SERVER" -ANe"$sqlcmd")
if [ -z "$rowcount" ]; then
    printf ":: Can't check for invalid rows in $PARENT_TABLE  ${RED}BAD${NC}\n"
elif [ "$rowcount" -gt 0 ]; then
    printf ":: Found invalid rows in $PARENT_TABLE  ${RED}BAD${NC}\n"
    echo ":: Use this query to find them: 

$sqlcmd
"
else
    printf ":: No invalid rows found in $PARENT_TABLE  ${GREEN}GOOD${NC}\n"
fi

## DDL?

ddl='
alter table `'$CHILD_DB'`.`'$CHILD_TABLE'`
add index `fk_idx_'$PARENT_DB'_'$PARENT_TABLE'_'$CHILD_DB'_'$CHILD_TABLE'` (
'$child_array'
)
;
'

echo ":: You might need to add an index:"
echo "$ddl"

ddl='
alter table `'$PARENT_DB'`.`'$PARENT_TABLE'`
add constraint `fk_'$PARENT_DB'_'$PARENT_TABLE'_'$CHILD_DB'_'$CHILD_TABLE'`
foreign key (
'$parent_array'
)
references `'$CHILD_DB'`.`'$CHILD_TABLE'` (
'$child_array'
)
on update RESTRICT
on delete RESTRICT
;
'

echo ":: And here is the foreign key ddl:"
echo "$ddl"

echo ':: To check for foreign key errors try: pt-fk-error-logger $(DSN '$LABEL')'
