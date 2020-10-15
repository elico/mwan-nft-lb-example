#!/usr/bin/env bash

ip netns|awk '{print $1}'|xargs -l1 -n1 ip netns del 

ip link delete edgebr0
ip link delete wanbr0

ruby create-lab-vrouters.rb

rm -f persist-src-to-dst-tuple
touch interfaces_counters

ip netns exec lan_gw ruby nftables-lb-wan.rb
ip netns exec lan_gw nft -f new-ruleset.nft

ip netns exec edge ruby tcp-server.rb &

ip netns exec client ping 8.8.8.8 -c 1
ip netns exec client ping google.com -c1

for i in {1..20}
do
  ip netns exec client ruby tcp-client.rb
done

ps aux|grep tcp-server|grep ruby|awk '{print $2}' |xargs -l1 -n1 kill
