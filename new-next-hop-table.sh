#!/usr/bin/env bash

NEXT_HOP_TABLE_NUMBER="$1"
GW="$2"
MARK="$3"

DTABLE="${NEXT_HOP_TABLE_NUMBER}"

echo ${DTABLE}
echo ${GW}

ip route flush table ${DTABLE}

ip route show | grep -Ev '^default' \
  | while read ROUTE ; do
   ip route add table ${DTABLE} ${ROUTE}
done

ip route add default via ${GW} table ${DTABLE}

DTABLE_SIZE=$(ip route show table ${DTABLE})
## Size is > 0

DTABLE_ROUTE_TEST=$(ip route get 8.8.8.8 mark 0x${MARK})
# Includes GW
