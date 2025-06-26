#!/bin/bash

CURRTIME=$(date +%s)
echo "Starting postgres-init script at `date`"

CTRL_TABLE_EXISTS=`psql -Aqt -c "select exists(select 1 from information_schema.tables where table_name = 'control_table')"`

if [[ "${CTRL_TABLE_EXISTS}" == "f" ]]; then
  TEMP_SQL_FILE="temp_01_basics.sql"
  sed "s/{{SCHEMA}}/${RPC_SCHEMA}/g" /scripts/sql/rpc/00_db-scripts/01_basics.sql > ${TEMP_SQL_FILE}
  psql -Aqt < ${TEMP_SQL_FILE}
fi

BLOCK_TABLE_EXISTS=`psql -Aqt -c "select exists(select 1 from information_schema.tables where table_name = 'block' and table_schema = 'public')"`

if [[ $BLOCK_TABLE_EXISTS == "f" ]]; then
  echo "Block table in public schema does not exist yet, aborting"
  exit 1
fi

DATE_DIFF=$(( $(date +%s) - $(date --date="$(psql -Aqt -c 'select time from block order by id desc limit 1;')" +%s) ))
echo "Date Diff is $DATE_DIFF"

[[ $DATE_DIFF -lt 7200 ]] || { echo "date difference greater than 7200 seconds, so exiting for later retry"; exit 1; }

echo "Block table seems to be on tip or close enough, current time is `date`"

IS_PG_INIT=`psql -Aqb -t -c "select exists(select 1 from information_schema.tables where table_name = 'control_table' and table_schema = '${RPC_SCHEMA}');"`
echo "PG_INIT is initially: $IS_PG_INIT"
if [[ $IS_PG_INIT == "t" ]]; then
  IS_PG_INIT=`psql -Aqb -t -c "select exists(select 1 from ${RPC_SCHEMA}.control_table where key = 'postgres_init_timestamp' and last_value is not null)"`
fi

echo "IS_POSTGRES_INITIALIZED is ${IS_PG_INIT}"

if [[ $IS_PG_INIT == "f" ]]; then
  echo "Commencing PG init..."
  ls -al /scripts/lib/install_postgres.sh
  /scripts/lib/install_postgres.sh > foo.out 2>&1
  echo "Done some stuff, curr time is $CURRTIME"
  cat foo.out
  psql -Aqb -c "INSERT INTO ${RPC_SCHEMA}.control_table (key, last_value) VALUES ('postgres_init_timestamp','${CURRTIME}');"
  echo "Done postgres init"
fi
