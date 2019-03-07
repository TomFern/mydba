#!/usr/bin/env bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
[[ -z "$CNFDIR" ]] && CNFDIR="$DIR/cnf"
. "$DIR"/cnf.sh import
set -o nounset

function usage () {
    echo "Usage :  $0 [options] [-- MYSQL_PARAMETERS] 
    Export CREATE DDL for tables, views, triggers, procedures/functions.
    One file per definition

    Config files:
        ./SERVER/mysql.cnf     --> [client] for server

    Example:
        Export all databases
            $0 -s SQL1 -o mydatabases

        Export 1 database
            $0 -s SQL1 -d MyDB -o backup

    Required:
        -s SERVER        Config name

    Options:
        -h|help     Display this message
        -d NAME     Dump only that schema (default: all schemas)
        -o OUTDIR   Output directory (default: .)
    "
}

if [ -z "$1" ]; then
    usage
    exit 0
fi

if ! tty >/dev/null; then
    exec &>/dev/null
fi
 

SERVER=
LABEL=
OUTDIR='.'
ONLYDB=
while getopts ":o:s:d:hv" opt
do
  case $opt in
      s) LABEL=$OPTARG;;
      o) OUTDIR=$OPTARG ;;
      d) ONLYDB=$OPTARG ;;
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

# OTHERARGS='--defaults-file="'$SERVER'"'
# echo --defaults-file="$SERVER" $OTHERARGS
# OTHERARGS=--defaults-file="$SERVER" $OTHERARGS" "$@

set -e
mkdir -p $OUTDIR

GREEN='\033[0;32m'
NC='\033[0m' # No Color

# TABLES

term_width=$(tput cols)
prw=$(($term_width - 20))
echo ""

TABLIST=
sqlcmd='
    SELECT CONCAT("`",TABLE_SCHEMA,"`.`",TABLE_NAME,"`") 
    FROM information_schema.tables 
    '"WHERE ENGINE in ('InnoDB','MyISAM','MEMORY') 
    AND TABLE_SCHEMA NOT IN ('sys','mysql','information_schema')
    AND (TABLE_SCHEMA = '$ONLYDB' or '$ONLYDB' = '' )
    ;"
for DBTAB in `mysql --defaults-file="$SERVER" $OTHERARGS -ANe "$sqlcmd"`
do
    TABLIST="${TABLIST} ${DBTAB}"
done
if [ -n "$TABLIST" ]; then
    for TYPEDBTAB in `echo "${TABLIST}"`
    do
        printf "\r:: ${GREEN}Table${NC}  %-${prw}s" "$TYPEDBTAB"
        DB=`echo "${TYPEDBTAB}" | sed 's/\./ /' | sed 's/\`//g' | awk '{print $1}'`
        TAB=`echo "${TYPEDBTAB}" | sed 's/\./ /' | sed 's/\`//g' | awk '{print $2}'`

        # if [ -z "$ONLYDB" ] || [ "$ONLYDB" == "$DB" ]; then
        SQLSTMT=`echo "SHOW CREATE TABLE ${TYPEDBTAB}\G"`
        if [ -z "$ONLYDB" ]; then
            mkdir -p $OUTDIR/$DB/tables
            TABFILE=${OUTDIR}/${DB}/tables/${TAB}.sql
            TABTEMP=${OUTDIR}/${DB}/tables/${TAB}.tmp
        else 
            mkdir -p $OUTDIR/tables
            TABFILE=${OUTDIR}/tables/${TAB}.sql
            TABTEMP=${OUTDIR}/tables/${TAB}.tmp
        fi

        mysql --defaults-file="$SERVER" $OTHERARGS -ANe"${SQLSTMT}" | sed 's/AUTO_INCREMENT=[0-9]*\s//g'> ${TABFILE}

        LINECOUNT=`wc -l < ${TABFILE}`
        if [ "$LINECOUNT" -gt 2 ]; then
            (( LINECOUNT -= 2 ))
            tail -${LINECOUNT} < ${TABFILE} > ${TABTEMP}

            cp -f ${TABTEMP} ${TABFILE}
            rm -f ${TABTEMP}
        fi
        # fi
    done
fi


# VIEWS

VIEWLIST=
sqlcmd=
sqlcmd='
    SELECT CONCAT("`",TABLE_SCHEMA,"`.`",TABLE_NAME,"`") 
    FROM information_schema.views 
    '" WHERE TABLE_SCHEMA NOT IN ('sys','mysql','information_schema')
    AND (TABLE_SCHEMA = '$ONLYDB' or '$ONLYDB' = '' )
    ;"
for DBVIEW in `mysql --defaults-file="$SERVER" $OTHERARGS -ANe "$sqlcmd"`
    # SELECT CONCAT(TABLE_SCHEMA,'.',TABLE_NAME) 
    # FROM information_schema.views 
    # WHERE TABLE_SCHEMA NOT IN ('sys','mysql','information_schema')
    # AND (TABLE_SCHEMA = '$ONLYDB' or '$ONLYDB' = '');"`
do
    VIEWLIST="${VIEWLIST} ${DBVIEW}"
done
if [ -n "$VIEWLIST" ]; then
    for TYPEDBVIEW in `echo "${VIEWLIST}"`
    do
        # echo $TYPEDBVIEW
        printf "\r:: ${GREEN}View${NC}  %-${prw}s" "$TYPEDBTAB"
        DB=`echo "${TYPEDBVIEW}" | sed 's/\./ /' | sed 's/\`//g' | awk '{print $1}'`
        VIEW=`echo "${TYPEDBVIEW}" | sed 's/\./ /' | sed 's/\`//g' | awk '{print $2}'`

        if [ -z "$ONLYDB" ] || [ "$ONLYDB" == "$DB" ]; then
            SQLSTMT=`echo "SHOW CREATE VIEW ${TYPEDBVIEW}\G"`
            if [ -z "$ONLYDB" ]; then
                mkdir -p $OUTDIR/$DB/views
                VIEWFILE=${OUTDIR}/${DB}/views/${VIEW}.sql
                VIEWTEMP=${OUTDIR}/${DB}/views/${VIEW}.tmp
            else 
                mkdir -p $OUTDIR/views
                VIEWFILE=${OUTDIR}/views/${VIEW}.sql
                VIEWTEMP=${OUTDIR}/views/${VIEW}.tmp
            fi
            mysql --defaults-file="$SERVER" $OTHERARGS -ANe"${SQLSTMT}" > ${VIEWFILE}

            LINECOUNT=`wc -l < ${VIEWFILE}`
            if [ "$LINECOUNT" -gt 2 ]; then
                (( LINECOUNT -= 2 ))
                tail -${LINECOUNT} < ${VIEWFILE} > ${VIEWTEMP}
            fi

            LINECOUNT=`wc -l < ${VIEWTEMP}`
            if [ "$LINECOUNT" -gt 2 ]; then
                (( LINECOUNT -= 2 ))
                head -${LINECOUNT} < ${VIEWTEMP} > ${VIEWFILE}
            fi

            rm -f ${VIEWTEMP}
        fi
    done
fi


# procedures & functions
SPLIST=
sqlcmd='
    SELECT CONCAT(lower(type),"@`",db,"`.`",name,"`") 
    FROM mysql.proc 
    '"WHERE db NOT IN ('mysql','sys','information_schema')
    AND (db = '$ONLYDB' or '$ONLYDB' = '');"
for DBSP in `mysql --defaults-file="$SERVER" $OTHERARGS -ANe"$sqlcmd"`
do
    SPLIST="${SPLIST} ${DBSP}"
done
if [ -n "$SPLIST" ]; then
    for TYPEDBSP in `echo "${SPLIST}"`
    do
        TYP=`echo "${TYPEDBSP}" | sed 's/@/ /' | sed 's/\./ /' | sed 's/\`//g' | awk '{print $1}'`
        DB=`echo "${TYPEDBSP}" | sed 's/@/ /' | sed 's/\./ /' | sed 's/\`//g' | awk '{print $2}'`
        SP=`echo "${TYPEDBSP}" | sed 's/@/ /' | sed 's/\./ /' | sed 's/\`//g' | awk '{print $3}'`
        printf "\r:: ${GREEN}$TYP${NC}  %-${prw}s" '`'${DB}'`'.'`'${SP}'`'

        SQLSTMT=`echo "SHOW CREATE ${TYPEDBSP}\G" | sed 's/@/ /'`
        if [ -z "$ONLYDB" ]; then
            mkdir -p $OUTDIR/$DB/${TYP}s
            SPFILE=${OUTDIR}/${DB}/${TYP}s/${SP}.sql
            SPTEMP=${OUTDIR}/${DB}/${TYP}s/${SP}.tmp
        else 
            mkdir -p $OUTDIR/${TYP}s
            SPFILE=${OUTDIR}/${TYP}s/${SP}.sql
            SPTEMP=${OUTDIR}/${TYP}s/${SP}.tmp
        fi

        mysql --defaults-file="$SERVER" $OTHERARGS -ANe"${SQLSTMT}" > ${SPFILE}

        LINECOUNT=`wc -l < ${SPFILE}`
        if [ "$LINECOUNT" -gt 3 ]; then
            (( LINECOUNT -= 3 ))
            tail -${LINECOUNT} < ${SPFILE} > ${SPTEMP}
        fi

        LINECOUNT=`wc -l < ${SPTEMP}`
        if [ "$LINECOUNT" -gt 3 ]; then
            (( LINECOUNT -= 3 ))
            head -${LINECOUNT} < ${SPTEMP} > ${SPFILE}
        fi
        rm -f ${SPTEMP}
    done
fi

# triggers

TRLIST=
sqlcmd='
    SELECT CONCAT("`",TRIGGER_SCHEMA,"`.`",TRIGGER_NAME,"`") 
    FROM information_schema.TRIGGERS 
    '" WHERE TRIGGER_SCHEMA NOT IN ('sys','mysql','information_schema')
    AND (TRIGGER_SCHEMA = '$ONLYDB' or '$ONLYDB' = '');"
for DBTR in `mysql --defaults-file="$SERVER" $OTHERARGS -ANe"$sqlcmd"`
do
    TRLIST="${TRLIST} ${DBTR}"
done
if [ -n "$TRLIST" ]; then
    for TYPEDBTR in `echo "${TRLIST}"`
    do
        printf "\r:: ${GREEN}Trigger${NC}  %-${prw}s" "$TYPEDBTR"
        DB=`echo "${TYPEDBTR}" | sed 's/@/ /' | sed 's/\./ /' | sed 's/\`//g' | awk '{print $1}'`
        TR=`echo "${TYPEDBTR}" | sed 's/@/ /' | sed 's/\./ /' | sed 's/\`//g'| awk '{print $2}'`

        SQLSTMT=`echo "SHOW CREATE TRIGGER ${TYPEDBTR}\G" | sed 's/@/ /'`

        if [ -z "$ONLYDB" ]; then
            mkdir -p $OUTDIR/$DB/triggers
            TRFILE=${OUTDIR}/${DB}/triggers/${TR}.sql
            TRTEMP=${OUTDIR}/${DB}/triggers/${TR}.tmp
        else 
            mkdir -p $OUTDIR/triggers
            TRFILE=${OUTDIR}/triggers/${TR}.sql
            TRTEMP=${OUTDIR}/triggers/${TR}.tmp
        fi
        mysql --defaults-file="$SERVER" $OTHERARGS -ANe"${SQLSTMT}" > ${TRFILE}

        LINECOUNT=`wc -l < ${TRFILE}`
        if [ "$LINECOUNT" -gt 3 ]; then
            (( LINECOUNT -= 3 ))
            tail -${LINECOUNT} < ${TRFILE} > ${TRTEMP}
        fi

        LINECOUNT=`wc -l < ${TRTEMP}`
        if [ "$LINECOUNT" -gt 3 ]; then
            (( LINECOUNT -= 3 ))
            head -${LINECOUNT} < ${TRTEMP} > ${TRFILE}
        fi
        rm -f ${TRTEMP}
    done
fi


# events

EVLIST=
sqlcmd='
    SELECT CONCAT("`",EVENT_SCHEMA,"`.`",EVENT_NAME,"`") 
    FROM information_schema.EVENTS 
    '" WHERE EVENT_SCHEMA NOT IN ('sys','mysql','information_schema')
    AND (EVENT_SCHEMA = '$ONLYDB' or '$ONLYDB' = '');"
for DBEV in `mysql --defaults-file="$SERVER" $OTHERARGS -ANe"$sqlcmd"`
do
    EVLIST="${EVLIST} ${DBEV}"
done
if [ -n "$EVLIST" ]; then
    for TYPEDBEV in `echo "${EVLIST}"`
    do
        printf "\r:: ${GREEN}Trigger${NC}  %-${prw}s" "$TYPEDBEV"
        DB=`echo "${TYPEDBEV}" | sed 's/@/ /' | sed 's/\./ /' | sed 's/\`//g' | awk '{print $1}'`
        EV=`echo "${TYPEDBEV}" | sed 's/@/ /' | sed 's/\./ /' | sed 's/\`//g'| awk '{print $2}'`

        SQLSTMT=`echo "SHOW CREATE EVENT ${TYPEDBEV}\G" | sed 's/@/ /'`

        if [ -z "$ONLYDB" ]; then
            mkdir -p $OUTDIR/$DB/events
            EVFILE=${OUTDIR}/${DB}/events/${EV}.sql
            EVTEMP=${OUTDIR}/${DB}/events/${EV}.tmp
        else 
            mkdir -p $OUTDIR/events
            EVFILE=${OUTDIR}/events/${EV}.sql
            EVTEMP=${OUTDIR}/events/${EV}.tmp
        fi
        mysql --defaults-file="$SERVER" $OTHERARGS -ANe"${SQLSTMT}" > ${EVFILE}

        LINECOUNT=`wc -l < ${EVFILE}`
        if [ "$LINECOUNT" -gt 4 ]; then
            (( LINECOUNT -= 4 ))
            tail -${LINECOUNT} < ${EVFILE} > ${EVTEMP}
        fi

        LINECOUNT=`wc -l < ${EVTEMP}`
        if [ "$LINECOUNT" -gt 3 ]; then
            (( LINECOUNT -= 3 ))
            head -${LINECOUNT} < ${EVTEMP} > ${EVFILE}
        fi
        rm -f ${EVTEMP}
    done
fi

echo ""
