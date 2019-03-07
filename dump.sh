#!/usr/bin/env bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
[[ -z "$CNFDIR" ]] && CNFDIR="$DIR/cnf"
. "$DIR"/cnf.sh import
set -o nounset

function usage () {
    echo "Usage :  $0 [options]  -- [OTHER OPTIONS FOR MYSQLDUMP]
    Dump databases with mysqldump

    Examples:

        Dump all DBs, single file, single transaction, works with replication
            $0 -s SQL1 -g -o /backups

        Dump all DBs, one file per DB
            $0 -s SQL1 -o /backups

        Single DB dump to STDOUT
            $0 -s SQL1 -d MYDB -o -

        Single table dump without data (create only)
            $0 -s SQL1 -d "MYDB MYTABLE" -o /backups -- --no-data

        Dump directly into other instance
            $0 -s SQL1 -d MYDB -o - | load.sh -s SQL2 -y MYDB

        Dump only procedures and functions
            $0 -s SQL1 -d MYDB -P -o . -- --routines --no-data


    Required:
        -s SERVER    Config
        -o OUTDIR   Output directory (use - for STDOUT)

    Options:
        -h|help     Display this message
        -g          Use a single transaction for user DBs (file: ALL_USER_DB.sql)
        -d NAME     Select only one 'DATABASE [TABLE]' to dump
        -P          Don't dump triggers, events, functions or procedures
        -H          Save on history table (if available)
    "
}

SERVER=
LABEL=
ONLYDB=
OUTDIR=
OUTPUT_STDOUT=
SW_g=
SW_H=
SW_P=
while getopts ":o:d:s:PHghyv" opt
do
  case $opt in
      P) SW_P=1;;
      s) LABEL=$OPTARG
          ;;
      H) SW_H=1;;
      g) SW_g=1;;
      o) OUTDIR=$OPTARG ;;
      d) ONLYDB=$OPTARG ;;
      y) :;;
      h|help     )  usage; exit 0   ;;
      * )  echo -e "\n  Option does not exist : $OPTARG\n"
          usage; exit 1   ;;
  esac
done
shift $(($OPTIND-1))
OTHERARGS=$@
ROUTINES=

if [ -z "$SW_P" ]; then
    ROUTINES="--routines --triggers --events"
fi

if [ -z "$LABEL" ]; then
    echo ":: Which config you want to use? (use -s option)" >&2
    exit 2
fi

SERVER=$(MyCnf "$LABEL" mysql)
[[ -z "$SERVER" ]] && echo ":: No config for $LABEL" && exit 1
DUMP=$(MyCnf "$LABEL" mysqldump)
[[ -z "$DUMP" ]] && echo ":: No mysqldump config for $LABEL" && exit 1

# dump location    
if [ -z "$OUTDIR" ]; then
    echo ":: Where do you want to dump the dbs? (use -o option)" >&2
    exit 6
fi

if [ "$OUTDIR" = "-" ]; then
    OUTPUT_STDOUT=1
else
    OUTDIR=$(readlink -f "$OUTDIR")
    mkdir -p "$OUTDIR"
    if [ ! -d "$OUTDIR" ]; then
        echo ":: Can't create dir $OUTDIR" >&2
        exit 1
    fi
fi

function pipe_message {
    if [ -z "$OUTPUT_STDOUT" ]; then
        cat
    fi
}

function log_to_history {

    file=$1
    db=$2
    begin=$3
    end=$4
    status=$5

    if [ -z "$SW_H" ]; then
        return
    fi

    HISTORY_CNF=$(MyCnf "$LABEL" history)
    size=0
    if [ -n "$OUTPUT_STDOUT" ]; then
        file="STDOUT"
    else
        if [ -f "$file" ]; then
            size=$(stat -c %s "$file")
        fi
    fi

    if [ -n "$HISTORY_CNF" ]; then
        STMT="INSERT INTO DBA.A_DUMPS (HOSTNAME,LABEL,PATH,FILE,DB,TS_BEGIN,TS_END,SIZE,STATUS)
        VALUES('$(hostname)','$LABEL','$OUTDIR','$file','$db','$begin','$end',$size,$status);"
        mysql --defaults-file="$HISTORY_CNF" -ANe"$STMT"
    fi
}

function check_gzip {
    fn=$1
    uncompressed=$(gzip -l "$fn" | tail -n 1 | awk '{print $2}')
    if [ "$uncompressed" -le 100 ]; then
        rm -f "$fn"
    fi
}

function pipe_output {
    fn=$1

    if [ -n "$OUTPUT_STDOUT" ]; then
        cat
    else
        gzip - > "$fn"
    fi
}


# start space monitoring
if [ -z "$OUTPUT_STDOUT" ] && [ -x "${DIR}"/kill-on-full.sh ]; then
    "$DIR"/kill-on-full.sh -c -o "$OUTDIR" -f 2 >/dev/null 2>&1
    status=$?
    if [ $status -ne 0 ]; then
        echo ":: Not enough free space on $OUTDIR. Too bad" >&2
        exit 10
    fi
    "$DIR"/kill-on-full.sh -p $$ -o "$OUTDIR" -f 2 &
fi


# backup only 1 db  - and exit
if [ -n "$ONLYDB" ]; then

    db="$ONLYDB"
    fn=$(echo "$db" | sed 's/ /_/g')
    fn="${OUTDIR}/${fn}.sql.gz"
    echo ":: $db -> $fn" | pipe_message
    begin=$(date +"%Y-%m-%d %H-%M-%S")
    mysqldump --defaults-file="$DUMP" \
        $ROUTINES --allow-keywords $OTHERARGS \
        $db | pipe_output "$fn"
    status=${PIPESTATUS[0]}||${PIPESTATUS[1]}
    end=$(date +"%Y-%m-%d %H-%M-%S")
    check_gzip "$fn"
    log_to_history "$fn" "$db" "$begin" "$end" "$status"
    exit $status

fi 


# backup all userdbs and mysql
listfn="${OUTDIR}/dump.txt"
if [ -f "$listfn" ]; then
    rm -f "$listfn"
    touch "$listfn"
fi


user_db_status=0
if [ -n "$SW_g" ]; then

    # single transaction - single file
    SQLSTMT="SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME NOT IN ('mysql', 'performance_schema', 'information_schema', 'sys'); "
    databases=$(mysql --defaults-file="$SERVER"  -ANe"$SQLSTMT")
    fn="${OUTDIR}/ALL_USER_DB.sql.gz"
    echo ":: $fn"  | pipe_message
    begin=$(date +"%Y-%m-%d %H-%M-%S")
    mysqldump --defaults-file="$DUMP" \
        $ROUTINES --allow-keywords --single-transaction --master-data=2 \
        $OTHERARGS --databases $(echo $databases | tr '\n' ' ') | pipe_output "$fn"
    status=${PIPESTATUS[0]}||${PIPESTATUS[1]}
    end=$(date +"%Y-%m-%d %H-%M-%S")
    user_db_status=$status
    check_gzip "$fn"
    while read db; do
        log_to_history "$fn" "$db" "$begin" "$end" "$status"
        echo "$db ALL_USER_DB.sql.gz $status" >> "$listfn"
    done <<< "$databases"

else

    # separate files
    SQLSTMT="SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME NOT IN ('mysql', 'performance_schema', 'information_schema', 'sys')"
    mysql --defaults-file="$SERVER" \
        -ANe"${SQLSTMT}" | awk '{print $1}' | while read db; do
            fn="${OUTDIR}/${db}.sql.gz"
            echo ":: $db -> $fn" | pipe_message
            begin=$(date +"%Y-%m-%d %H-%M-%S")
            mysqldump --defaults-file="$DUMP" \
                $ROUTINES --allow-keywords \
                $OTHERARGS "$db" | pipe_output "$fn"
            status=${PIPESTATUS[0]}||${PIPESTATUS[1]}
            user_db_status=${user_db_status}||$status
            end=$(date +"%Y-%m-%d %H-%M-%S")
            check_gzip "$fn"
            log_to_history "$fn" "$db" "$begin" "$end" "$status"
            echo "$db ${db}.sql.gz $status" >> "$listfn" 
    done

fi
sleep 2

mkdir -p "$OUTDIR"/system
fn="${OUTDIR}/system/mysql.sql.gz"
begin=$(date +"%Y-%m-%d %H-%M-%S")
echo ":: mysql -> $fn"
mysqldump --defaults-file="$DUMP" mysql | gzip - > "$fn"
status=${PIPESTATUS[0]}||${PIPESTATUS[1]}
end=$(date +"%Y-%m-%d %H-%M-%S")
check_gzip "$fn"
log_to_history "$fn" "$db" "$begin" "$end" "$status"

"$DIR"/rowcount.sh -s "$LABEL" > "$OUTDIR/rowcount.txt"
"$DIR"/grants.sh -s "$LABEL" > "$OUTDIR/grants.sql"

exit $user_db_status
