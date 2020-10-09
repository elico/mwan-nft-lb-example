#!/usr/bin/env bash

# https://serverfault.com/questions/618857/list-all-route-tables

set -x

ip rule

set +x

for i in $(ip route show table all | grep "table" | sed 's/.*\(table.*\)/\1/g' | awk '{print $2}' | sort | uniq | grep -e "[0-9]");do
  echo "Table: $i"
  echo "============"
  set -x
  ip route show table $i
  set +x
done

set +x
