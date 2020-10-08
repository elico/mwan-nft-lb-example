#!/usr/bin/env bash

DEST_NET="192.168.111.0/24"

NEXT_HOPS="2"

NEXT_HOP_1="192.168.126.202"
NEXT_HOP_2="192.168.126.203"

NEXT_HOP_1_TABLE="202"
NEXT_HOP_2_TABLE="203"

NFTABLES="/usr/sbin/nft"
IPTABLES="/sbin/iptables"
IP="/sbin/ip"

LAN="eth0"
WAN="eth1"

## Disabling Reverse path filter
for i in /proc/sys/net/ipv4/conf/*/rp_filter
do
  echo $i
  cat $i
  echo 0 > $i
done


DTABLE="${NEXT_HOP_1_TABLE}"

$IP route del ${DEST_NET}

$IP route flush table ${DTABLE}

$IP route show | grep -Ev '^default' \
  | while read ROUTE ; do
    $IP route add table ${DTABLE} ${ROUTE}
done

$IP route add default via ${NEXT_HOP_1} table ${DTABLE}

DTABLE="${NEXT_HOP_2_TABLE}"

$IP route flush table ${DTABLE}
$IP route show | grep -Ev "^default" \
  | while read ROUTE ; do
    $IP route add table ${DTABLE} ${ROUTE}
done

$IP route add default via ${NEXT_HOP_2} table ${DTABLE}


$IP route add ${DEST_NET} via ${NEXT_HOP_1}


#NAT
${NFTABLES} add table nat
${NFTABLES} add chain ip nat postrouting '{ type nat hook postrouting priority 100; policy accept; }'
${NFTABLES} add rule nat postrouting oif ${WAN} masquerade

# MANGLE
${NFTABLES} add table mangle

${NFTABLES} add chain ip mangle prerouting '{ type filter hook prerouting priority -150; policy accept; }'
${NFTABLES} add chain ip mangle input '{ type filter hook input priority -150; policy accept; }'
${NFTABLES} add chain ip mangle forward '{ type filter hook forward priority -150; policy accept; }'
${NFTABLES} add chain ip mangle output '{ type route hook output priority -150; policy accept; }'
${NFTABLES} add chain ip mangle postrouting '{ type filter hook postrouting priority -150; policy accept; }'


${NFTABLES} add chain ip mangle wan1
${NFTABLES} add rule ip mangle wan1 counter ct mark set 0x1

${NFTABLES} add chain ip mangle wan2
${NFTABLES} add rule ip mangle wan2 counter ct mark set 0x2

# 5-tuple/flow/PCC LOAD Balance
${NFTABLES} add chain ip mangle PCC_OUT_TCP
${NFTABLES} add rule ip mangle PCC_OUT_TCP counter jhash ip saddr . tcp sport . ip daddr . tcp dport mod 2 vmap { 0 : jump wan1, 1 : jump wan2 }

${NFTABLES} add chain ip mangle PCC_OUT_UDP
${NFTABLES} add rule ip mangle PCC_OUT_UDP counter jhash ip saddr . udp sport . ip daddr . udp dport mod 2 vmap { 0 : jump wan1, 1 : jump wan2 }

${NFTABLES} add chain ip mangle PCC_OUT_OTHERS
${NFTABLES} add rule ip mangle PCC_OUT_OTHERS counter ip protocol { tcp, udp }  return
${NFTABLES} add rule ip mangle PCC_OUT_OTHERS counter jhash ip saddr . ip daddr mod 2 vmap { 0 : jump wan1, 1 : jump wan2 }


${NFTABLES} add rule ip mangle prerouting counter meta mark set ct mark
${NFTABLES} add rule ip mangle prerouting ct mark != 0x0 counter ct mark set mark
${NFTABLES} add rule ip mangle prerouting iifname "${LAN}" ip protocol tcp ct state new counter jump PCC_OUT_TCP
${NFTABLES} add rule ip mangle prerouting iifname "${LAN}" ip protocol udp ct state new counter jump PCC_OUT_UDP
${NFTABLES} add rule ip mangle prerouting iifname "${LAN}" ct state new counter jump PCC_OUT_OTHERS


${NFTABLES} add rule ip mangle prerouting ct mark 0x1 counter meta mark set 0x1
${NFTABLES} add rule ip mangle prerouting ct mark 0x2 counter meta mark set 0x2

${NFTABLES} add rule ip mangle postrouting counter ct mark set mark

$IP rule|grep  "from all fwmark 0x1 lookup ${NEXT_HOP_1_TABLE}" >/dev/null
if [ "$?" -eq "1" ]; then
          $IP rule add fwmark 1 table ${NEXT_HOP_1_TABLE}
fi

$IP rule|grep  "from all fwmark 0x2 lookup ${NEXT_HOP_2_TABLE}" >/dev/null
if [ "$?" -eq "1" ]; then
          $IP rule add fwmark 2 table ${NEXT_HOP_2_TABLE}
fi