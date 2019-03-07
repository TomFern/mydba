#!/usr/bin/env bash
# load databases or run batches

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
[[ -z "$CNFDIR" ]] && CNFDIR="$DIR/cnf"
. "$DIR"/cnf.sh import
set -o nounset

function usage () {
    echo "Usage :  $0 [options]  -- [OTHER OPTIONS FOR MYSQL]
    Load backups created with dump.sh or run sql batches.

    Examples:
        Load all from dumps from dir
            $0 -s SQL1 -o /backups

        Load a directly from dump file (reads from STDIN)
            zcat /backups/MyDB.sql.gz | $0 -s SQL1 -N -d MyDB

        Load a single db from dumpfile from an older mysql version
            $0 -s SQL1 -f MyDB.sql.gz -U

        Load with upgrade and ignore errors
            zcat MyDB.sql.gz | filter-upgrade-dump.sh | $0 -s SQL1 -d MyDB -- --force

        Load enter interactive console
            $0 -s SQL1

    Required:
        -s SERVER      Config name

    Options:
        -h|help       Display this message
        -d NAME       Database name
        -f DUMPFILE   Load a database from DUMPFILE
        -o DUMPDIR    Load database(s) from DUMPDIR
        -W TIMEOUT    If file or dir is not found, wait TIMEOUT seconds instead of failing
        -H            Save to history table (if available)
        -K            Kill connections to DB 
        -KK           Killall other connections to server (DANGEROUS!)
        -y            Don't ask for confirmation
    "
}

# colors
RED='\033[0;31m'
NC='\033[0m' # No Color

MODE=std
SERVER=
LABEL=
OUTDIR=
OUTFILE=
DBNAME=
WAIT_TIMEOUT=
SW_y=
SW_H=
SW_N=
SW_K=0
while getopts ":o:f:s:W:d:KNHUyhv" opt
do
  case $opt in
      d) DBNAME=$OPTARG;;
      s) LABEL=$OPTARG ;;
      N) SW_N=1;;
      y) SW_y=1;;
      W) WAIT_TIMEOUT=$OPTARG;;
      o) OUTDIR=$OPTARG; MODE=load ;;
      f) OUTFILE=$OPTARG; MODE=load ;;
      K) SW_K=$((SW_K+1));;
      H) SW_H=1;;
      h|help     )  usage; exit 0   ;;
      * )  echo -e "\n  Option does not exist : $opt\n"
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

if [ -z "$DBNAME" ]; then
    echo ":: Database not set (use -d option)" >&2
    exit 3
fi

# load dump from location?
if [ -n "$OUTDIR" ]; then
    OUTDIR=$(readlink -f "$OUTDIR")
    if [ ! -d "$OUTDIR" ]; then
        echo ":: Can't find dir $OUTDIR" >&2
        exit 1
    fi
fi

function kill_connections {
    database=$1

    if [ $SW_K -eq 1 ]; then

        stmt="select id from information_schema.processlist where user not in ('event_scheduler','system user') and DB='$database';"

        for pid in $(mysql --defaults-file="$SERVER" -ANe"$stmt"); do
            if [ -n "$pid" ]; then
                mysql --defaults-file="$SERVER" -ANe"kill $pid;"
            fi
        done

    elif [ $SW_K -gt 1 ]; then

        stmt="select id from information_schema.processlist where user not in ('event_scheduler','system user');"

        for pid in $(mysql --defaults-file="$SERVER" -ANe"$stmt"); do
            if [ -n "$pid" ]; then
                mysql --defaults-file="$SERVER" -ANe"kill $pid;"
            fi
        done
    fi
}

function show_server {

    socket=$(awk -F '=' '/socket/ {print $2}' "$SERVER" | head -n 1 | tr -d ' ')
    port=$(awk -F '=' '/port/ {print $2}' "$SERVER" | head -n 1 | tr -d ' ')
    host=$(awk -F '=' '/host/ {print $2}' "$SERVER" | head -n 1 | tr -d ' ')
    username=$(awk -F '=' '/user/ {print $2}' "$SERVER" | head -n 1 | tr -d ' ')

    echo ":: Target server"
    printf "     Host: ${RED}$host${NC}\n"
    printf "     User: ${RED}$username${NC}\n"
    printf "     Port: ${RED}$port${NC}\n"
    printf "     Socket: ${RED}$socket${NC}\n"

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
    if [ "$MODE" = "std" ]; then
        file="STDIN"
    else
        if [ -f "$file" ]; then
            size=$(stat -c %s "$file")
        fi
    fi

    if [ -n "$HISTORY_CNF" ]; then
        STMT="INSERT INTO DBA.A_LOADS (HOSTNAME,LABEL,PATH,FILE,DB,TS_BEGIN,TS_END,SIZE,STATUS)
        VALUES('$(hostname)','$LABEL','$OUTDIR','$file','$db','$begin','$end',$size,$status);"
        mysql --defaults-file="$HISTORY_CNF" -ANe"$STMT"
    fi
}

function wait_for_file {
    fn="$1"

    if [ ! -f "$fn" ]; then
        if [ -n "$WAIT_TIMEOUT" ]; then
            waiting=$WAIT_TIMEOUT
            while [ "$waiting" -ge 0 ]; do
                if [ -f "$fn" ]; then
                    break;
                fi
                sleep 1
                waiting=$(($waiting - 1))
            done
        fi
    fi

    if [ ! -f "$fn" ]; then
        echo ":: File not found: $fn" >&2
        exit 2
    fi

}



function test_list {

    echo ":: User DB file list" >&2
    ok=1
    while read db fn st; do
        if [ ! -f "$OUTDIR/$fn" ]; then
            echo "$db  $fn is missing  ERROR" >&2
            ok=0
        elif [ "$st" -ne 0 ]; then
            echo "$db  status $st  ERROR" >&2
            ok=0
        else
            echo "$db  OK" >&2
        fi
    done < "$listfn"
    if [ $ok -eq 0 ]; then
        exit 2
    fi

}

if [ -n "$SW_N" ]; then
    SCHEMA_NOTHING=$(mysql --defaults-file="$SERVER" -ANe "show databases like '$DBNAME';")
    if [ -n "$SCHEMA_NOTHING" ]; then
        echo ":: Schema $DBNAME already exists! Delete it first." >&2
        exit 4
    fi
    SCHEMA_EXISTS=$(mysql --defaults-file="$SERVER" -ANe "show databases like '$DBNAME';")
    if [ -z "$SCHEMA_EXISTS" ]; then
        mysql --defaults-file="$SERVER" -ANe "CREATE SCHEMA $DBNAME;"
    fi
fi

show_server

if [ "$MODE" = "std" ]; then

    # interative mode
    exec 3<&0
    export MYSQL_PS1='\U:\p[\d]>' 
    cat <&3 | mysql --defaults-file="$SERVER" --comments --show-warnings $OTHERARGS $DBNAME
    # mysql --defaults-file="$SERVER" --comments --show-warnings $OTHERARGS <&3
    st=$?

elif [ "$MODE" = "load" ]; then


    if [ -n "$OUTFILE" ]; then

        wait_for_file "$OUTFILE"

        if [ -z "$SW_y" ]; then
            read -p ":: Are you sure you want to load database '$DBNAME'? (y/n)" -n 1 -r
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo ":: Bye" >&2
                exit 2
            fi
            echo "" >&2
        fi

        echo ":: Loading '$DBNAME' from '$OUTFILE' ..." 
        kill_connections "$DBNAME"
        begin=$(date +"%Y-%m-%d %H-%M-%S")
        zcat "$OUTFILE" | mysql --defaults-file="$SERVER" --comments --show-warnings $OTHERARGS $DBNAME
        st=${PIPESTATUS[0]}||${PIPESTATUS[1]}||${PIPESTATUS[2]}
        end=$(date +"%Y-%m-%d %H-%M-%S")
        log_to_history "$OUTFILE" "$DBNAME" "$begin" "$end" "$st"

    else

        # batch mode
        listfn="${OUTDIR}/userdb.list"
        wait_for_file "$listfn"

        test_list

        if [ -z "$SW_y" ]; then
            read -p ":: Are you sure you want to load the DBs? (y/n)" -n 1 -r
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo ":: Bye" >&2
                exit 2
            fi
            echo "" >&2
        fi

        if [ -f "$OUTDIR/ALL_USER_DB.sql.gz" ]; then
            echo ":: Loading all user DBs ..." >&2
            begin=$(date +"%Y-%m-%d %H-%M-%S")
            zcat "$OUTDIR/ALL_USER_DB.sql.gz" | mysql --defaults-file="$SERVER" --comments --show-warnings $OTHERARGS
            st=${PIPESTATUS[0]}||${PIPESTATUS[1]}||${PIPESTATUS[2]}
            end=$(date +"%Y-%m-%d %H-%M-%S")
            log_to_history "$fn" "$db" "$begin" "$end" "$st"
        else 
            st=0
            while read db fn nada; do
                echo ":: Loading $db ..." >&2
                kill_connections "$db"
                begin=$(date +"%Y-%m-%d %H-%M-%S")
                zcat "$OUTDIR/$fn"  | mysql --defaults-file="$SERVER" --comments --show-warnings $OTHERARGS "$db"
                st=${PIPESTATUS[0]}||${PIPESTATUS[1]}||${PIPESTATUS[2]}
                end=$(date +"%Y-%m-%d %H-%M-%S")
                log_to_history "$fn" "$db" "$begin" "$end" "$st"
            done < "$listfn"
        fi
    fi
fi

if [ $st -ne 0 ]; then
    echo ":: if you are having errors to load, you might want to try -U or -- --force" >&2
fi

exit $st
