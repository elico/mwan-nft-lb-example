#!/usr/bin/env bash

for i in /proc/sys/net/ipv4/conf/*/rp_filter
do
  echo $i
  cat $i
  echo 0 > $i
done