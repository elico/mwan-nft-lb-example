#!/usr/bin/env ruby

require "open3"
require "json"

$debug_cmds=0

id=2000

vrouter_id="vrouter_#{id}"

def system_quietly(cmd)
    exit_status = nil
    stdout = nil
    stderr = nil

    stdout, stderr, exit_status = Open3.capture3(cmd)
    stdout = "" if stdout == nil
    stderr = "" if stderr == nil
    ret = {"cmd" => cmd , "stdout" => stdout.lines , "stderr" => stderr.lines , "code" => exit_status.to_i, "ok" =>  exit_status.to_i == 0 , "exit_status" => exit_status }
    return ret
end

def ether_interfaces()
    arr = []
    system_quietly("ip -o l")["stdout"].each do |l|
        parts = l.split
        if parts[15] =~ /^link\/ether/
            arr << parts[1].gsub(":","")
        end
    end
    return arr
end

commands = []
execution_errors = []

ether_interfaces_list = ether_interfaces()

commands << "ip netns del #{vrouter_id}"

commands << "ip netns add #{vrouter_id}"
commands << "ip netns exec #{vrouter_id} ip link add #{vrouter_id} type dummy"
commands << "ip netns exec #{vrouter_id} ip link set #{vrouter_id} up"
commands << "ip netns exec #{vrouter_id} ip link set lo up"

ether_interfaces_list.sort.each do |interface| 
    macvlan_interface_name="macvlan#{rand(1000..2000)}"

    commands << "ip link add #{macvlan_interface_name} link #{interface} type macvlan mode bridge"
    commands << "ip link set #{macvlan_interface_name} netns #{vrouter_id}"
    commands << "ip netns exec #{vrouter_id} ip link set #{macvlan_interface_name} name #{interface}"
    commands << "ip netns exec #{vrouter_id} ip link set #{interface} up"
end

("05".."15").each do |net|
    interface="ether#{net.gsub(/^0/, "")}"
    commands << "ip netns exec #{vrouter_id} ip address add 192.168.2#{net}.100/24 dev #{interface}"
end

commands << "ip netns exec #{vrouter_id} ip address add 192.168.125.254/24 dev ether23"

[ "net.ipv4.ip_forward" , "net.ipv4.ip_forward_use_pmtu" ].each do |parameter|
    commands << "ip netns exec #{vrouter_id} sysctl -w #{parameter}=1"
end

puts("Executing #{commands.size} shell commands:")

commands.each_with_index do |cmd,i|
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
