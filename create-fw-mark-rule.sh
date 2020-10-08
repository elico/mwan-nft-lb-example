#!/usr/bin/env bash

MARK="0x$1"
TABLE=$2

RULE=$(ip rule|grep "from all fwmark 0x${MARK} ")
RES=$?
if [ "$RES" -eq "0" ]; then
	ip rule del from all fwmark 0x${MARK}
fi

ip rule add fwmark ${MARK} table ${TABLE}
