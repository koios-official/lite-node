#!/bin/bash

cd ${CNODE_HOME}/scripts
source ./env offline || exit 1
progress="$(${CCLI} query tip --testnet-magic ${NWMAGIC} --socket-path ${SOCKET} | jq -r .syncProgress 2>/dev/null | cut -d. -f1 )"
[[ ${progress} -lt 100 ]] && exit 1 || exit 0
