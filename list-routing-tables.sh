#!/usr/bin/env bash

# https://serverfault.com/questions/618857/list-all-route-tables

ip route show table all | grep "table" | sed 's/.*\(table.*\)/\1/g' | awk '{print $2}' | sort | uniq

#ip route show table all | grep -Po 'table \K[^\s]+' | sort -u

#ip route show table all | grep "table" | sed 's/.*\(table.*\)/\1/g' | awk '{print $2}' | sort | uniq | grep -e "[0-9]"

#ip route show table all | grep -Po 'table \K[^\s]+' | sort -u | grep -e "[0-9]"
