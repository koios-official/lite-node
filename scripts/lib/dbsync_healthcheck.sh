#!/bin/bash

export PGPASSWORD=${POSTGRES_PASSWORD}
[[ $(( $(date +%s) - $(date --date="$(psql -U ${POSTGRES_USER} -d ${POSTGRES_DB} -h ${POSTGRES_HOST} -qt -c 'select time from block order by id desc limit 1;')" +%s) )) -lt 3600 ]] || exit 1

sed -i 's#"value": "bootstrap"#"value": "prune"#g' /dbsync-cfg/*.json
sed -i 's#"ledger": "ignore"#"ledger": "disable"#g' /dbsync-cfg/*.json
