#!/usr/bin/env bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
[[ -z "$CNFDIR" ]] && CNFDIR="$DIR/cnf"
. "$DIR"/cnf.sh import
set -o nounset

function usage () {
    echo "Usage :  $0 -s SERVER 'CALL Database.Procedure_name(param1,param2,...);'"
}

LABEL=
CALLSTR=
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
CALLSTR=$@


[[ -z "$LABEL " ]] && ":: Use -s option to set the SERVER"
SERVER=$(MyCnf "$LABEL" mysql)
[[ -z "$SERVER" ]] && echo ":: No config for $LABEL" && exit 1

if [ -z "$CALLSTR" ]; then
    usage
    exit 3
fi

call_fqdn=$(echo "$CALLSTR" | sed 's/^\s*call\s*//i' |  sed 's/(/ /' | awk '{print $1}' | sed 's/ //g')
call_procname=$(echo "$call_fqdn" | awk -F. '{print $2}')

dbname=
call_dbname=
if [ -n "$call_procname" ]; then
    call_dbname=$(echo "$call_fqdn" | awk -F. '{print $1}')
    dbname="$call_dbname"
# else
#     call_procname=$(echo "$call_fqdn" | awk -F. '{print $1}')
#     dbname=$DATABASE
fi

call_argstr=$(echo "$CALLSTR" | cut -d "(" -f2 | cut -d ")" -f1 | sed 's/^\s*//' | sed 's/\*$//')

# get show procedure
proc_proto=$(
    mysql --defaults-file="$SERVER" -ANe'SHOW CREATE PROCEDURE `'$dbname'`.`'$call_procname'`\G' | \
        head -n 4 | \
        tail -n 1
    )
proc_args=$(echo "$proc_proto" | sed 's/([0-9]*)//g' | cut -d "(" -f2 | cut -d ")" -f1 | sed 's/^\s*//' | sed 's/\*$//')
proc_code=$(
    mysql --defaults-file="$SERVER" -ANe'SHOW CREATE PROCEDURE `'$dbname'`.`'$call_procname'`\G' | \
        head -n -4 | \
        tail -n +6
    )

if [ -z "$proc_code" ] || [ -z "$proc_proto" ]; then
    echo ":: couldn't get procedure definition "$code""
    exit 2
fi

# get nth column for a line in csv
function csv_extract_col {
    icol=$1
    line=$2
    echo "$line" | awk -F, '{
  for (i=1; i<=NF; i++) {
    if (s) {
      if ($i ~ "\"$") {print s","$i; s=""}
      else s = s","$i
    }
    else {
      if ($i ~ "^\".*\"$") print $i
      else if ($i ~ "^\"") s = $i
      else print $i
    }
  }
}' | sed $icol'q;d' | sed 's/^\s*//' | sed 's/\*$//'
}

proto=$(mktemp --suffix=.sql)
code=$(mktemp --suffix=.sql)

echo "-- 
-- CALL $dbname.$call_procname($call_argstr)
--
-- Parameters:" > "$proto"
echo "$proc_code" > "$code"

i=1
while true; do
    pval=$(csv_extract_col $i "$call_argstr" )
    if [ -z "$pval" ]; then
        break
    fi
    pname=$(csv_extract_col $i "$proc_args")
    if [ -z "$pname" ]; then
        break
    fi
    # echo "pname=$pname" >&2
    pname=$(echo "$pname" | cut -d' ' -f 2)

    echo "--   $pname=$pval" >> "$proto"

    sed -i 's/\b'$pname'\b/'$pval'/g' "$code"
    i=$(($i+1))
done
echo "--" >> "$proto"

cat "$proto" "$code" 

if which xclip >/dev/null 2>&1; then
    xclip -i -selection primary < "$code"
    xclip -i -selection clipboard < "$code"
fi

rm -f "$proto"
rm -f "$code"
