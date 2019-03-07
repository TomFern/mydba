# DBA Tools: MySQL

## Quickstart

Most scripts need your servers connection parameters.

```
# Add config for a server
cnf.sh add SQL1 -u david -P SuperSecret123 -h SERVER1 -p 3306 -s /var/lib/mysql/mysql.sock -c /etc/my.cnf
# Test connection
cnf.sh ping SQL1
# Now SQL1 is available for your scripts
dump.sh -s SQL1 -d MyDB -o /backups
```


## Backup & Restore

* dump.sh: wrapper mysqldump
* load.sh: restore backups taken with dump.sh
* snap.sh: wrapper for innobackupex/xtrabackup (superuser)
* reimage.sh: restore backup taken with snap.sh (superuser)
* filter-rename-dump.sh: filter to rename schema in mysqldump output (beta!)
* grants.sh: export user GRANTs
* schema-ddl.sh: export CREATE DDL for all objects in DB
* schema-merge.sh: import schema objects generated with schema-ddl.sh (beta!)



## Replication

* heartbeat.sh: monitor delay using pt-heartbeat
* repl-setup.sh: setup replication config

```
alert=$(heartbeat.sh -s SQL1 -l 60)
if [ -n "$alert" ]; then
   echo "$alert" | mail -s "Replication Alert!" dba@example.com
fi
```

## Misc

* beacon.sh: unwrap procedure calls into equivalent-ish statements

```
beacon.sh -s SQL1 "CALL DB1.MyProcedure(arg1,arg2,arg3);"
```

* delete-binlogs.sh: delete binary logs based on age
* cycle-errorlogs.sh: cycle the servers logs
* fk-advisor: advise on FK constraint creation
* kill-on-full.sh: monitor free space on disk
* profile-db: use pt-query-digest to profile server
* rowcount.sh: rudimentary db/table/row counter
* table-copy.sh: copy tables using pt-table-sync
* trigger-ddl.sh: generate trigger DDL to keep table in sync
* rename-db: rename a database (beta!)

