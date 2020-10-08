#!/usr/bin/env bash

NEXT_HOP_TABLE_NUMBER="$1"
GW="$2"

DTABLE="${NEXT_HOP_TABLE_NUMBER}"

echo ${DTABLE}
echo ${GW}

ip route flush table ${DTABLE}

ip route show | grep -Ev '^default' \
  | while read ROUTE ; do
   ip route add table ${DTABLE} ${ROUTE}
done

ip route add default via ${GW} table ${DTABLE}
