#!/usr/bin/env bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
[[ -z "$CNFDIR" ]] && CNFDIR="$DIR/cnf"
. "$DIR"/cnf.sh import
set -o nounset

function usage () {
    echo "Usage :  $0 [options]  -- [OTHER OPTIONS FOR INNOBACKUPEX]
    XtraBackup/innobackupex MySQL Snapshot

    Hardcoded options: 
        rsync - if installed
        full backup only

    Examples:
            $0 -s SQL1 -o /backups

    Required:
        -s SERVER   Config name
        -o OUTDIR   Output directory (default: CWD)

    Options:
        -h|help     Display this message
        -t          Backup to a timestamped subdir
        -H          Log result in history table
        -Z          Don't compress snapshot (qpress)
    "
}

LABEL=
SERVER=
OUTDIR=
SW_Z=1
SW_t=
SW_H=
while getopts ":o:s:tHZhv" opt
do
  case $opt in
      s) LABEL=$OPTARG
          ;;
      Z) SW_Z='';;
      H) SW_H=1;;
      t) SW_t=1;;
      o) OUTDIR=$OPTARG ;;
      h)  usage; exit 0   ;;
      * )  echo -e "\n  Option does not exist : $OPTARG\n"
          usage; exit 1   ;;
  esac
done
shift $(($OPTIND-1))
OTHERARGS=$@

if ! which innobackupex >/dev/null 2>&1; then
    echo ":: innobackupex not found in path, you must keep working"
    exit 3
fi

if [ -z "$LABEL" ]; then
    echo ":: Which config you want to use? (use -s option)"
    exit 2
fi
SERVER=$(MyServer "$LABEL")
[[ -z "$SERVER" ]] && echo ":: No config for $LABEL" && exit 1

SERVER_SOCKET=$(MyConfig "$LABEL" socket)
if [ -z "$SERVER_SOCKET" ]; then
    echo ":: Socket path not set" >&2
    exit 2
fi
SERVER_CNF=$(MyConfig "$LABEL" server_cnf)
if [ -z "$SERVER_CNF" ]; then
    echo ":: Server config path not in set" >&2
    exit 2
fi
DUMP=$(MyCnf "$LABEL" mysqldump) 
[[ -z "$DUMP" ]] && echo ":: No mysqldump config for $LABEL" && exit 1

# use history?
HISTORY_CNF=
if [ -n "$SW_H" ]; then
    HISTORY_CNF=$(MyCnf "$LABEL" history)
fi

# dump location    
if [ -z "$OUTDIR" ]; then
    echo ":: Where do you want to dump the dbs? (use -o option)"
    exit 6
fi

OUTDIR=$(readlink -f "$OUTDIR")
mkdir -p "$OUTDIR"
if [ ! -d "$OUTDIR" ]; then
    echo ":: Can't create dir $OUTDIR"
    exit 1
fi


function log_to_history {
    begin=$1
    end=$2
    status=$3

    echo "# Snapshot created with snap.sh
# Hostname: $(hostname)
# System: MySQL
# Server: $LABEL
# Path: $OUTDIR
# Type: FULL
# Started: $begin
# Ended: $end
# Status code: $status" > "$OUTDIR/snapshot.info"

    if [ -n "$HISTORY_CNF" ]; then
        size=$(du -s "$OUTDIR" | awk '{print $1}')
        STMT="INSERT INTO DBA.A_SNAPS (HOSTNAME,LABEL,PATH,TYPE,TS_BEGIN,TS_END,SIZE,STATUS) 
        VALUES('$(hostname)','$LABEL','$OUTDIR','F','$begin','$end',$size,$status);"
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

# start space monitoring
if [ -x "${DIR}"/kill-on-full.sh ]; then
    "$DIR"/kill-on-full.sh -c -o "$OUTDIR" -f 2 >/dev/null 2>&1
    status=$?
    if [ $status -eq 10 ]; then
        echo ":: Not enough free space on $OUTDIR. Too bad!"
        exit 10
    fi
    "$DIR"/kill-on-full.sh -p $$ -o "$OUTDIR" -f 2 &
fi


begin=$(date +"%Y-%m-%d %H-%M-%S")
if [ -z "$SW_t" ]; then
    OTHERARGS="--no-timestamp $OTHERARGS"
fi
if [ -n "$SW_Z" ]; then
    OTHERARGS="--compress $OTHERARGS"
fi
if which rsync >/dev/null 2>&1; then
    OTHERARGS="--rsync $OTHERARGS"
fi

username=$(MyConfig $LABEL user)
password=$(MyConfig $LABEL password)

# take snapshot with innobackupex
SNAPDIR="$OUTDIR"/snap
innobackupex --defaults-file="$SERVER_CNF" \
    --backup \
    --slave-info \
    --user="$username" \
    --password="$password" \
    --socket="$SERVER_SOCKET" \
    $OTHERARGS "$SNAPDIR"
status=$?
end=$(date +"%Y-%m-%d %H-%M-%S")

if [ $status -ne 0 ]; then
    echo ":: innobackupex ended with status: $status"
    exit $status
fi

log_to_history "$begin" "$end" "$status"

# system dump & grants
"$DIR"/grants.sh -s "$LABEL" > "$OUTDIR/grants.sql"
mkdir -p "$OUTDIR"/system
fn="${OUTDIR}/system/mysql.sql.gz"
mysqldump --defaults-file="$DUMP" mysql | gzip - > "$fn"
check_gzip "$fn"

