#!/usr/bin/env bash

for i in $(ip rule|grep "from all fwmark" |awk '{print $7 }'|xargs -l1 -n1);do
  echo "Removing routing table: $i"
  ip route flush table $i
done

for i in $(ip rule|grep "from all fwmark" |awk '{print $5 }'|xargs -l1 -n1);do
  echo "Removing routing rule fwmark: $i"
  ip rule del from all fwmark $i
done


