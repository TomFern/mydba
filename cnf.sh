#!/usr/bin/env bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
[[ -z "$CNFDIR" ]] && CNFDIR="$DIR/cnf"

function usage () {
    echo "Usage :  $0 [COMMAND] [[SERVER]] [OPTIONS]
    Config helper tool+library

    CLI Usage:

      Commands:
        help
        import
        add SERVER [-u USER -P PASSWORD -s socket -h host -p port -c /etc/my.cnf]
            add a new config
        history HISTORY_SERVER SERVER1 SERVER2 ...
            Set HISTORY for SERVERS
        master MASTER_SERVER SLAVE1 SLAVE2 ...
            Set MASTER for slave servers
        ping SERVER 
            Test connection 
        cat SERVER [-d]
            cat mysql.cnf or mysqldump.cnf
        my SERVER [-d] -- [EXTRA ARGS]
            Spawn mysql client

      Options:
        -d          Use mysqldump.cnf file

      Config files generated with add:
        SERVER/mysql.cnf     --> [client] server to dump
        SERVER/mysqldump.cnf --> [mysqldump] server to dump
        SERVER/config        --> settings for scripts

    Library usage:

      Source lib for scripting:
        . cnf.sh import

      Functions:
        My SERVER: spawn MYSQL_CLIENT
        DSN SERVER [EXTRA,PARAMS]: return DSN string
        MyURI SERVER [EXTRA/ARGS]: return uri string
        MyServer SERVER: return path to config dir
        MyCnf SERVER: return path to mysql.cnf
        MyDumpCnf SERVER: return path to mysqldump.cnf
        MyConfig SERVER PARAMETER: return PARAMETER from config
        MyPing SERVER: test connection
    "
}

COMMAND=$1
SERVER=
LABEL=

if [ -n "$1" ]; then
    COMMAND=$1
    shift
fi
if [ -n "$1" ]; then
    LABEL=$1
    shift
fi
#         && [ -n "$2" ]; then
#     shift 
#     if [ -n "$1" ]; then
#         LABEL=$1
#         shift
#     fi
# fi

SERVER_CNF=
USERNAME=$USER
PASSWORD=
SERVER_HOST=localhost
SERVER_PORT=3306
SERVER_SOCKET=
SW_d=
while getopts ":P:p:u:c:h:p:s:d" opt
do
    case $opt in
        d) SW_d=1;;
        c) SERVER_CNF=$OPTARG;;
        p) SERVER_PORT=$OPTARG;;
        h) SERVER_HOST=$OPTARG;;
        s) SERVER_SOCKET=$OPTARG;;
        u) USERNAME=$OPTARG;;
        p) PASSWORD=$OPTARG;;
        P) PASSWORD=$OPTARG;;
        * )  echo -e "\n  Option does not exist : $OPTARG\n"
             usage; exit 1   ;;
    esac
done
shift $(($OPTIND-1))
OTHERARGS=$@

function MyServer {
    label=$1
    server="${CNFDIR}/$label"
    if [ -d "$server" ] && [ -f "$server/mysql.cnf" ] && [ -f "$server/mysqldump.cnf" ]; then
        echo "$server"
    else
        echo "ERROR (MyServer): directory not found for $label" >&2
    fi
}
# export -f MyServer

function MyConfig {
    label=$1
    param=$2
    config_file="${CNFDIR}/$label/config"
    if [ ! -r "$config_file" ]; then
        echo "ERROR: can't read config file $config_file" >&2
    else
        awk -F '=' '/'$param'/ {print $2}' "$config_file" | head -n 1 | tr -d ' '
    fi

    
}
# export -f MyConfig


function MyCnf {
    label=$1
    fn=$2
    cnf_file="$CNFDIR/$label/${fn}.cnf"
    if [ -r "$cnf_file" ]; then
        echo "$cnf_file"
    else
        echo "ERROR (MyCnf): file not found $cnf_file" >&2
    fi
}
# export -f MyCnf

# function MySysbench {
#     label=$1
#     shift
#     otherargs=$@

#     client_cnf=$(MyCnf "$label" mysql)
#     if [ -n "$client_cnf" ]; then
#         host=$(awk -F '=' '/host/ {print $2}' "$client_cnf" | head -n 1 | tr -d ' ')
#         port=$(awk -F '=' '/port/ {print $2}' "$client_cnf" | head -n 1 | tr -d ' ')
#         # socket=$(awk -F '=' '/socket/ {print $2}' "$client_cnf" | head -n 1 | tr -d ' ')
#         username=$(awk -F '=' '/user/ {print $2}' "$client_cnf" | head -n 1 | tr -d ' ')
#         password=$(awk -F '=' '/password/ {print $2}' "$client_cnf" | head -n 1 | tr -d ' ')

#         args="--db-driver=mysql --mysql-user=$username --mysql-host=$host"
#         if [ -n "$password" ]; then
#             args=$args" --mysql-password=$password"
#         fi
#         if [ -n "$port" ]; then
#             args=$args" --mysql-port=$port"
#         fi
#         echo "${args}$otherargs"
#     fi
# }

function MyURI {
    label=$1
    shift
    otherargs=$@

    client_cnf=$(MyCnf "$label" mysql)
    if [ -n "$client_cnf" ]; then
        host=$(awk -F '=' '/host/ {print $2}' "$client_cnf" | head -n 1 | tr -d ' ')
        port=$(awk -F '=' '/port/ {print $2}' "$client_cnf" | head -n 1 | tr -d ' ')
        # socket=$(awk -F '=' '/socket/ {print $2}' "$client_cnf" | head -n 1 | tr -d ' ')
        username=$(awk -F '=' '/user/ {print $2}' "$client_cnf" | head -n 1 | tr -d ' ')
        password=$(awk -F '=' '/password/ {print $2}' "$client_cnf" | head -n 1 | tr -d ' ')

        uri="${username}:$password@${host}"
        if [ -n "$port" ]; then
            uri=$uri":${port}"
        fi
        echo "${uri}$otherargs"
    fi
}

function MyArgs {
    label=$1
    shift
    format=$@

    client_cnf=$(MyCnf "$label" mysql)
    if [ -n "$client_cnf" ]; then
        host=$(awk -F '=' '/host/ {print $2}' "$client_cnf" | head -n 1 | tr -d ' ')
        port=$(awk -F '=' '/port/ {print $2}' "$client_cnf" | head -n 1 | tr -d ' ')
        socket=$(awk -F '=' '/socket/ {print $2}' "$client_cnf" | head -n 1 | tr -d ' ')
        username=$(awk -F '=' '/user/ {print $2}' "$client_cnf" | head -n 1 | tr -d ' ')
        password=$(awk -F '=' '/password/ {print $2}' "$client_cnf" | head -n 1 | tr -d ' ')

        args=$format
        args=${args/¬user¬/$username}
        # if [ -n "$socket" ]; then
        #     args=${args/¬socket¬/$socket}
        args=${args/¬port¬/$port}
        args=${args/¬host¬/$host}
        args=${args/¬password¬/$password}
        echo $args
    fi
    
}

function DSN {
    label=$1
    shift
    otherargs=$@

    client_cnf=$(MyCnf "$label" mysql)
    if [ -n "$client_cnf" ]; then
        host=$(awk -F '=' '/host/ {print $2}' "$client_cnf" | head -n 1 | tr -d ' ')
        port=$(awk -F '=' '/port/ {print $2}' "$client_cnf" | head -n 1 | tr -d ' ')
        socket=$(awk -F '=' '/socket/ {print $2}' "$client_cnf" | head -n 1 | tr -d ' ')
        username=$(awk -F '=' '/user/ {print $2}' "$client_cnf" | head -n 1 | tr -d ' ')
        password=$(awk -F '=' '/password/ {print $2}' "$client_cnf" | head -n 1 | tr -d ' ')

        dsn="u=$username"
        if [ -n "$socket" ]; then
            dsn=$dsn",S=$socket"
        elif [ -n "$port" ]; then
            dsn=$dsn",P=$port"
        fi

        if [ -n "$host" ]; then
            dsn=$dsn",h=$host"
        fi
        if [ -n "$password" ]; then
            dsn=$dsn",p=$password"
        fi
        echo "${dsn},$otherargs"
    fi
}

# function My {
#     label=$1
#     shift
#     otherargs=$@
#     client_cnf=$(MyCnf "$label" mysql)
#     if [ -n "$client_cnf" ]; then
#         mysql --defaults-file="$client_cnf" $otherargs
#     fi
# }

function MyPing {
    label=$1
    client_cnf=$(MyCnf "$label" mysql)
    mysql --defaults-file="$client_cnf" -ANe"SELECT 1 FROM DUAL;" >/dev/null 
}
# export -f MyPing


if [ -z "$COMMAND" ]; then
    usage
elif [ "$COMMAND" = "import" ]; then
    # do nothing
    :
elif [ -z "$LABEL" ]; then # "$COMMAND" != "import" ]; then
    echo "ERROR: no SERVER was supplied" >&2
    usage
    exit 2
else

    SERVER="${CNFDIR}"/"$LABEL"
    case "$COMMAND" in

        add)
            mkdir -p "$SERVER"
            if [ ! -d "$SERVER" ]; then
                echo ":: Unable to create dir $SERVER"
                exit 2
            fi

            echo "# MySQL Config for $LABEL" > "$SERVER"/config

            if [ -r "$SERVER_CNF" ]; then
                SERVER_HOST=$(cat "$SERVER_CNF" | egrep -v '^\s*#' | egrep -i '\s*host' | awk -F= '{print $2}' | sed 's/^\s*\|\s*$//g')
                SERVER_PORT=$(cat "$SERVER_CNF" | egrep -v '^\s*#' | egrep -i '\s*port' | awk -F= '{print $2}' | sed 's/^\s*\|\s*$//g')
                SERVER_SOCKET=$(cat "$SERVER_CNF" | egrep -v '^\s*#' | egrep -i '\s*socket' | awk -F= '{print $2}' | sed 's/^\s*\|\s*$//g' | head -n 1)
                echo "server_cnf=$SERVER_CNF" >> "$SERVER"/config
            fi

            echo "[mysql]" > "$SERVER/mysql.cnf"
            echo "[mysqldump]" > "$SERVER/mysqldump.cnf"

            if [ -n "$USERNAME" ]; then
                echo "user=$USERNAME" >> "$SERVER/config"
                echo "user=$USERNAME" >> "$SERVER/mysql.cnf"
                echo "user=$USERNAME" >> "$SERVER/mysqldump.cnf"
            fi

            if [ -n "$SERVER_HOST" ]; then
                echo "host=$SERVER_HOST" >> "$SERVER/config"
                echo "host=$SERVER_HOST" >> "$SERVER/mysql.cnf"
                echo "host=$SERVER_HOST" >> "$SERVER/mysqldump.cnf"
            fi
            if [ -n "$SERVER_PORT" ]; then
                echo "port=$SERVER_PORT" >> "$SERVER/config"
                echo "port=$SERVER_PORT" >> "$SERVER/mysql.cnf"
                echo "port=$SERVER_PORT" >> "$SERVER/mysqldump.cnf"
            fi
            if [ -n "$SERVER_SOCKET" ]; then
                echo "socket=$SERVER_SOCKET" >> "$SERVER/config"
                echo "socket=$SERVER_SOCKET" >> "$SERVER/mysql.cnf"
                echo "socket=$SERVER_SOCKET" >> "$SERVER/mysqldump.cnf"
            fi
            if [ -n "$PASSWORD" ]; then
                echo "password=$PASSWORD" >> "$SERVER/config"
                echo "password=$PASSWORD" >> "$SERVER/mysql.cnf"
                echo "password=$PASSWORD" >> "$SERVER/mysqldump.cnf"
            fi

            chmod 700 "$SERVER"
            chmod 600 "$SERVER"/*
            ;;

        config)
            fn=$1
            echo $(MyCnf "$LABEL" "$fn")
            ;;

        history)

            link_to=$1
            while [ -n "$link_to" ]; do
                (cd "$CNFDIR/$link_to"; ln -f -s ../"$LABEL"/mysql.cnf history.cnf)
                shift
                link_to=$1
            done
            ;;

        master)

            link_to=$1
            while [ -n "$link_to" ]; do
                (cd "$CNFDIR/$link_to"; ln -f -s ../"$LABEL"/mysql.cnf slave.cnf)
                shift
                link_to=$1
            done
            ;;

        cat)
            if [ -n "$SW_d" ]; then
                cat $(MyCnf "$LABEL" mysqldump)
            else
                cat $(MyCnf "$LABEL" mysql)
            fi
            ;;
        my)
            My $LABEL $OTHERARGS
            ;;

        ping)
            MyPing $LABEL
            ;;

        help) usage;;
        * ) echo "ERROR: COMMAND $COMMAND not supported" >&2; usage;;
    esac
# fi
fi
