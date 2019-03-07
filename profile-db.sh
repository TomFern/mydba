#!/usr/bin/env bash
# profile db usage with pt-query-digest

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PATH=$PATH:$DIR
[[ -z "$CNFDIR" ]] && CNFDIR="$DIR/cnf"
. "$DIR"/cnf.sh import
set -o nounset

function usage () {
    echo "Usage :  $0 [options] 
    Profile db usage hijacking slow log with pt-query-digest

    Config files:
        ./SERVER/mysql.cnf  --> [client] for data source server

    Examples:
        Profile server until interrupted
            $0 -s SQL1

        Profile a database until interrupted
            $0 -s SQL1 -d DATABASE -u USR1


    Required:
        -s SERVER    Config name for DBA History

    Options:
        -d NAME     Profile specific database
        -u USER     Profile specific user
        -c HOST     Profile specific host or IP address
        -h|help     Display this message
    "
}

SERVER=
LABEL=
DBNAME=
DBUSER=
DBHOST=
date=$(date +"%Y%m%d-%H%M%S")
while getopts ":s:d:u:c:h" opt
do
  case $opt in
      c) DBHOST=$OPTARG ;;
      s) LABEL=$OPTARG ;;
      d) DBNAME=$OPTARG ;;
      u) DBUSER=$OPTARG;;
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
[[ -z "$LABEL " ]] && ":: Use -s option to set the SERVER"
SERVER=$(MyCnf "$LABEL" mysql)
[[ -z "$SERVER" ]] && echo ":: No config for $LABEL" && exit 1

function get_parameter {
    parameter=$1
    mysql --defaults-file="$SERVER" -ANe "select @@${parameter};"
}

function set_parameter {
    parameter=$1
    value=$2
    mysql --defaults-file="$SERVER" -ANe "set GLOBAL ${parameter}=${value};"
}

true_slow_query_log=$(get_parameter "slow_query_log")
true_slow_query_log_file=$(get_parameter "slow_query_log_file")
true_long_query_time=$(get_parameter "long_query_time")
temp_slow_query_log_file=$(echo "$true_slow_query_log_file" | sed 's/.log$//' | sed 's/$/_profile_'$date'/')

if [ -z "$true_slow_query_log_file" ]; then
    echo ":: Unable get slow log config"
    exit 1
fi

if [ ! -r "$true_slow_query_log_file" ]; then
    echo ":: No read permissions for slow log files. Try again using a service account"
    exit 1
fi

echo ":: Changing slow log settings temporarily
  slow_query_log:      $true_slow_query_log -> ON
  slow_query_log_file: $true_slow_query_log_file -> ${temp_slow_query_log_file}.log
  long_query_time:     $true_long_query_time -> 0
"

set_parameter "slow_query_log" "OFF"
set_parameter "slow_query_log_file" "'${temp_slow_query_log_file}.log'"
set_parameter "long_query_time" "0"
set_parameter "slow_query_log" "ON"

echo ":: Run you processes now and send interrupt CTRL-C when ready to continue ..."
trap " " INT
tail -f "${temp_slow_query_log_file}.log"
trap - INT

set_parameter "slow_query_log" "OFF"
set_parameter "slow_query_log_file" "'${true_slow_query_log_file}'"
set_parameter "long_query_time" "${true_long_query_time}"
set_parameter "slow_query_log" "${true_slow_query_log}"

# --since
# --until

filter="1"
if [ -n "$DBNAME" ]; then
    filter=$filter' && $event->{db} && ($event->{db} || "") =~ m/'$DBNAME'/'
fi
if [ -n "$DBUSER" ]; then
    filter=$filter' && ($event->{user} || "") =~ m/'$DBUSER'/'
fi
if [ -n "$DBHOST" ]; then
    filter=$filter' && ($event->{host} || $event->{ip} || "") =~ m/'$DBHOST'/'
fi

# report file
report_file=
touch "${temp_slow_query_log_file}.txt" 2>/dev/null
if [ -w "${temp_slow_query_log_file}.txt" ]; then
    report_file="${temp_slow_query_log_file}.txt"
elif [ -w "$PWD" ]; then
    report_file="$PWD/"$(basename "$temp_slow_query_log_file")".txt"
else
    report_file="/tmp/"$(basename "$temp_slow_query_log_file")".txt"
fi

pt-query-digest --filter '$filter' $OTHERARGS < "${temp_slow_query_log_file}.log" > "$report_file"
echo ":: Slow log: ${temp_slow_query_log_file}.log"
echo ":: Profile: $report_file"
less "$report_file"


