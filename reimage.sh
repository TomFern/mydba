#!/usr/bin/env bash
# restore an xtrabackup/innobackupex instance snapshot

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
[[ -z "$CNFDIR" ]] && CNFDIR="$DIR/cnf"
set -o nounset

function usage () {
    echo "Usage :  $0 [options]  -- [OTHER OPTIONS FOR INNOBACKUPEX]
    Restore an XtraBackup/innobackupex MySQL Snapshot taken with snap.sh

    Examples:
            $0 -o /backups

    Required:
        -o BACKUPDIR   Backup snapshot directory

    Options:
        -c CONFIG   Path to config file (default: BACKUPDIR/my.cnf)
        -h|help     Display this message
    "
}

OUTDIR=
CNF=
while getopts ":o:c:hv" opt
do
  case $opt in
      c) CNF=$OPTARG;;
      o) OUTDIR=$OPTARG ;;
      h|help     )  usage; exit 0   ;;
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


if [ -z "$OUTDIR" ]; then
    echo ":: You must supply the backup dir (use -o switch)"
    exit 2
fi

OUTDIR=$(readlink -f "$OUTDIR")
if [ ! -d "$OUTDIR" ]; then
    echo ":: Can't find dir $OUTDIR"
    exit 1
fi

# begin=$(date +"%Y-%m-%d %H-%M-%S")
if [ -z "$CNF" ]; then
    CNF="$OUTDIR/my.cnf"
fi

if [ ! -f "$CNF" ]; then
    echo ":: Can't find config file (you can also use -c switch)"
    exit 2
fi

mysql --defaults-file="$CNF" -ANe"SELECT 1 FROM DUAL;" >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo ":: Seems that the mysql service is running!. Please stop it and try again."
    exit 2
fi

datadir=$(cat "$CNF" | egrep -v '^\s*#' | egrep -i '\s*datadir' | awk -F= '{print $2}' | sed 's/^\s*\|\s*$//g')
svc_user=$(cat "$CNF" | egrep -v '^\s*#' | egrep -i '\s*user' | awk -F= '{print $2}' | sed 's/^\s*\|\s*$//g')
if [ $(find "$datadir" | egrep -v '\.cnf$' | wc -l) -gt 0 ]; then
    echo ":: Seems that there are files on $datadir. Please delete/move them and try again"
    exit 2
fi

echo ":: Please confirm these parameters:
datadir=$datadir
user=$svc_user"
read -p ":: Are you sure you want to restore snapshot? (y/n)" -n 1 -r
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo ":: Bye"
    exit 2
fi
echo ""

if [ $(find "$OUTDIR/snap" -name "*.qp" | wc -l) -gt 0 ]; then
    if ! which qpress >/dev/null 2>&1; then
        echo ":: qpress not found in path, you must keep working"
        exit 3
    fi
    echo ":: Running decommpress"
    innobackupex  --decompress "$OUTDIR/snap"
fi

if [ $(find "$OUTDIR/snap" -maxdepth 1 -name "ib_logfile*" | wc -l) -eq 0 ]; then
    echo ":: Running apply-log/prepare"
    innobackupex --apply-log "$OUTDIR/snap"
fi


read -p ":: Ready to restore files. This is your last chance to cancel. Confirm? (y/n)" -n 1 -r
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo ":: Bye"
    exit 2
fi
echo ""

echo ":: Restoring files to $datadir"
innobackupex --defaults-file="$CNF" --move-back "$OUTDIR/snap"
chown $svc_user:$svc_user -R "$datadir"

