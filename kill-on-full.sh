#!/usr/bin/env bash
# kill process and its childs on low disk space

trap 'echo Caught signal' TERM INT

F_PCT=5
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
function usage () {
    echo "Usage :  $0 [options] 
    Kill process and its childs on low free space

    Examples:

        Check free space:
            $0 -c -f 10 -p /backups
            if $?; then echo 'ok'; fi

        Monitor backup process and kill on 5% free
            $0 -p 1234 -p /backups -f 5

    Options:
        -h|help     Display this message
        -p PID      PID to kill
        -o PATH     Path/mountpoint to monitor (default: pwd)
        -f PCT      Free percent threshold (default: $F_PCT)
        -c          Only check space and exit (STATUS = 10 -> not enough space left)
    "
}


OUTDIR=$(pwd)
SW_c=
M_PID=
while getopts ":o:f:p:ch" opt
do
  case $opt in
      p) M_PID=$OPTARG ;;
      f) F_PCT=$OPTARG ;;
      o) OUTDIR=$OPTARG ;;
      c) SW_c=1;;
      h|help     )  usage; exit 0   ;;
      * )  echo -e "\n  Option does not exist : $OPTARG\n"
          usage; exit 1   ;;
  esac
done
shift $(($OPTIND-1))
OTHERARGS=$@

function check_space {
    fp=$1
    pp=$2
    usepct=$(df -P "$fp" |  awk '{print $5}' |  sed '1d;s/%//')
    freepct=$(( 100 - $usepct ))
    if [ $? -ne 0 ]; then
        echo ":: Failed to check free space. That's too bad"
        exit 2
    fi
    if [ "$freepct" -gt "$pp" ]; then
        return 0
    else
        return 1
    fi
}

if [ -n "$SW_c" ]; then
    if check_space "$OUTDIR" "$F_PCT"; then
        exit 0
    else
        exit 10

    fi
fi

if [ "$F_PCT" -le 0 ]; then
    cho ":: Threshold is 0 or less. Nothing to be done"
    exit 0
fi

if [ -z "$M_PID" ]; then
    echo ":: No PID supplied"
    exit 0
fi

while true; do
    if ps "$M_PID" >/dev/null 2>&1; then
        if ! check_space "$OUTDIR" "$F_PCT"; then
            echo ":: Threshold triggered. Pushing the button"
            if which pkill >/dev/null 2>&1; then
                echo ":: Killing child processes"
                pkill -P "$M_PID"
            fi
            echo ":: Killing $M_PID"
            kill "$M_PID"
            exit 1
        fi
    else
        echo ":: PID $M_PID not found. Nothing left to do"
        exit 0
    fi
    sleep 1
done

