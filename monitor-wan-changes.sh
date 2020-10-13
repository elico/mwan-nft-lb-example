#!/usr/bin/env bash

WAN_STATE_FILE="/var/run/wan_monitor/status"

touch "${WAN_STATE_FILE}"

# initialize nftables with vmap with ${CURRENT_WAN_STATE}
# in my case: ruby nftables-lb-wan.rb

while true; do

LAST_WAN_STATE=$(cat ${WAN_STATE_FILE} |xargs)
CURRENT_WAN_STATE=$(ls /var/run/wan_monitor/up/ |xargs)

if [ "${LAST_WAN_STATE}" == "${CURRENT_WAN_STATE}" ];then
	echo "No Change"
	sleep 1
else
	echo "Changed from: \"${LAST_WAN_STATE}\" => \"${CURRENT_WAN_STATE}\""
	# regenerate vmap with ${CURRENT_WAN_STATE}
	# in my case: ruby nftables-lb-wan.rb
	echo "${CURRENT_WAN_STATE}" > "${WAN_STATE_FILE}"
fi
done
