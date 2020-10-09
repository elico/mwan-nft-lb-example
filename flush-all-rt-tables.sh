#!/usr/bin/env bash


for i in $(ip route show table all | grep "table" | sed 's/.*\(table.*\)/\1/g' | awk '{print $2}' | sort | uniq | grep -e "[0-9]");do
  echo "Removig Table: $i"
  ip route flush table $i
done
