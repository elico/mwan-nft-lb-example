#!/usr/bin/env ruby

require "open3"
require "json"

$debug_cmds = 0

def system_quietly(cmd)
  exit_status = nil
  stdout = nil
  stderr = nil

  stdout, stderr, exit_status = Open3.capture3(cmd)
  stdout = "" if stdout == nil
  stderr = "" if stderr == nil
  ret = { "cmd" => cmd, "stdout" => stdout.lines, "stderr" => stderr.lines, "code" => exit_status.to_i, "ok" => exit_status.to_i == 0, "exit_status" => exit_status }
  return ret
end

commands = []
execution_errors = []

# Client: ether0: 192.168.125.100/24
# Lan GW: ether23: 192.168.125.254/24 + ether:5-15: 192.168.205-215.100/24
# 10 WAN Routers: 2 nics
# 1 WAN edge NAT Router

client = "client"
lan_gw = "lan_gw"
wan_routers = []
("05".."15").each do |r|
  wan_routers << "wan_r#{r}"
end
edge_router = "edge"

namespaces = []
namespaces << client
namespaces << lan_gw
namespaces << edge_router
wan_routers.each { |r| namespaces << r }

# Creating namespaces
namespaces.each do |ns|
  commands << "ip netns add #{ns}"
  commands << "ip netns exec #{ns} ip link set lo up"
  commands << "ip netns exec #{ns} sysctl -w net.ipv4.ip_forward=1"
  commands << "ip netns exec #{ns} sysctl -w net.ipv4.ip_forward_use_pmtu=1"
end

# Creating bridges
["wanbr0", "edgebr0"].each do |bridge|
  commands << "ip link add name #{bridge} type bridge"
  commands << "ip link set #{bridge} up"
end

# Setting up client interfaces
commands << "ip link add l-veth1 type veth peer name r-veth1"
commands << "ip link set l-veth1 netns #{client}"

commands << "ip netns exec #{client} ip link set l-veth1 name ether0"

commands << "ip netns exec #{client} ip link set ether0 up"
commands << "ip netns exec #{client} ip addr add 192.168.125.100/24 dev ether0"
commands << "ip netns exec #{client} ip route add default via 192.168.125.254"

commands << "ip link set r-veth1 netns #{lan_gw}"

commands << "ip netns exec #{lan_gw} ip link set r-veth1 name ether23"
commands << "ip netns exec #{lan_gw} ip link set ether23 up"
commands << "ip netns exec #{lan_gw} ip addr add 192.168.125.254/24 dev ether23"

("05".."15").each do |interface|
  i = interface
  interface = interface.gsub(/^0/, "")

  commands << "ip link add l-lgw-ether#{interface} type veth peer name r-lgw-e#{interface}"
  commands << "ip link set l-lgw-ether#{interface} netns #{lan_gw}"

  commands << "ip netns exec #{lan_gw} ip link set l-lgw-ether#{interface} name ether#{interface}"
  commands << "ip netns exec #{lan_gw} ip link set ether#{interface} up"

  commands << "ip netns exec #{lan_gw} ip addr add 192.168.2#{i}.100/24 dev ether#{interface}"

  commands << "ip link set r-lgw-e#{interface} up"
  commands << "ip link set r-lgw-e#{interface} master wanbr0"
end

wan_routers.each do |wan_r|
  ns = wan_r
  wan_r = wan_r.gsub("_", "-")

  commands << "ip link add l-#{wan_r}-lan type veth peer name r-#{wan_r}-lan"
  commands << "ip link set l-#{wan_r}-lan netns #{ns}"
  commands << "ip netns exec #{ns} ip link set l-#{wan_r}-lan name ether1"
  commands << "ip netns exec #{ns} ip link set ether1 up"
  commands << "ip netns exec #{ns} ip addr add 192.168.2#{wan_r.gsub("wan-r", "")}.254/24 dev ether1"

  commands << "ip link set r-#{wan_r}-lan up"
  commands << "ip link set r-#{wan_r}-lan master wanbr0"

  commands << "ip link add l-#{wan_r}-wan type veth peer name r-#{wan_r}-wan"
  commands << "ip link set l-#{wan_r}-wan netns #{ns}"
  commands << "ip netns exec #{ns} ip link set l-#{wan_r}-wan name ether0"
  commands << "ip netns exec #{ns} ip link set ether0 up"
  commands << "ip netns exec #{ns} ip addr add 192.168.101.#{wan_r.gsub("wan-r", "").gsub(/^0/, "")}/24 dev ether0"
  commands << "ip netns exec #{ns} ip route add default via 192.168.101.254"
  commands << "ip netns exec #{ns} iptables -t nat -A POSTROUTING -o ether0 -j MASQUERADE"

  commands << "ip link set r-#{wan_r}-wan up"
  commands << "ip link set r-#{wan_r}-wan master edgebr0"
end

# Edge router

commands << "ip link add edge-wan link ether0 type macvlan mode bridge"

commands << "ip link set edge-wan netns #{edge_router}"
commands << "ip netns exec #{edge_router} ip link set edge-wan name ether0"
commands << "ip netns exec #{edge_router} ip link set ether0 up"
commands << "ip netns exec #{edge_router} ip addr add 192.168.89.99/24 dev ether0"
commands << "ip netns exec #{edge_router} ip route add default via 192.168.89.254"
commands << "ip netns exec #{edge_router} iptables -t nat -A POSTROUTING -o ether0 -j MASQUERADE"

commands << "ip link add l-#{edge_router}-lan type veth peer name r-#{edge_router}-lan"
commands << "ip link set l-#{edge_router}-lan netns #{edge_router}"
commands << "ip netns exec #{edge_router} ip link set l-#{edge_router}-lan name ether1"
commands << "ip netns exec #{edge_router} ip link set ether1 up"
commands << "ip netns exec #{edge_router} ip addr add 192.168.101.254/24 dev ether1"

commands << "ip link set r-#{edge_router}-lan up"
commands << "ip link set r-#{edge_router}-lan master edgebr0"

# ("5".."15").each do |ip|
#   commands << "ip netns exec #{edge_router} ping 192.168.101.#{ip} -c 2"
# end

commands << "ip netns exec #{edge_router} ping 192.168.101.5 -c 2"
commands << "ip netns exec #{edge_router} ping 192.168.89.254 -c 2"

puts("Executing #{commands.size} shell commands:")

commands.each_with_index do |cmd, i|
  res = system_quietly(cmd)
  ret = "CMD #{i} => #{JSON.pretty_generate(res)}"
  execution_errors << ret if !res["ok"]
  STDERR.puts(ret) if $debug_cmds > 0
end

puts("Finsihed Executing #{commands.size} shell commands!")

if execution_errors.size > 0
  execution_errors.each do |error|
    STDERR.puts(error)
  end
end
