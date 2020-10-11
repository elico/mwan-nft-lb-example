#!/usr/bin/env ruby

require "open3"
require "json"

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

my_dir = __dir__

commands = []
nftables_commands = []
execution_errors = []

$debug_cmds = 0
$flush_tables = true
$delete_tables = true
$use_nft_vm = true

$interfaces_counters = false
$interfaces_counters = true if File.exist?("#{my_dir}/interfaces_counters")

$use_mark_as_table = true

$jhash_distribution = "5-tuple"
$jhash_distribution = "srcip+dstip+dstport" if File.exist?("#{my_dir}/persist-src-to-dst-tuple")

five_tuple="ipprotocol+srcip+proto_src_port+dstip+proto_dst_port"

four_tuple="srcip+proto_src_port+dstip+proto_dst_port"

three_tuple= [ "srcip+proto_src_port+dstip" ,
"srcip+dstip+proto_dst_port" ,
"proto_src_port+dstip+proto_dst_port",
"srcip+proto_src_port+proto_dst_port",
"proto_src_port+dstip+proto_dst_port",
"ipprotocol+srcip+dstip"
 ]

two_tuple = [ "srcip+dstip"]

port_based_ip_protocols = [ "udp", "udplite", "tcp", "dccp", "sctp" ]

counters_ip_protocols = [ "icmp", "esp", "ah", "comp", "udp", "udplite", "tcp", "dccp", "sctp" ]

jump_format = "both"

jump_format = "table" if $use_mark_as_table

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

ether_interfaces_list = ether_interfaces()

wan_interfaces = {}

lan_interfaces = []

$rt_tables = {}
$rt_marks = {}

def gen_rt_table(interface)
    while true do
        table = rand(1000..2000).to_s
        if $rt_tables[table] == nil
            $rt_tables[table] = interface
            return table
        else
            next
        end
    end
end

def gen_rt_mark(interface)
    while true do
        mark = rand(1000..2000).to_s
        if $rt_marks[mark] == nil
            $rt_marks[mark] = interface
            return mark
        else
            next
        end
    end
end


tmp_interfaces = File.readlines("#{my_dir}/wan_interfaces.list")

tmp_interfaces.each do |line|
    next if line =~ /^#/

    parts = line.strip.split
    next if parts.size < 4

    interface_name = parts[0].strip
    interface_gw = parts[1].strip
    interface_rt_table = parts[2].strip
    interface_rt_mark = parts[3].strip

    # overriding dynamic rt_mark with the rt_table value
    interface_rt_mark = interface_rt_table if $use_mark_as_table

    # Valid interface name
    next if !ether_interfaces_list.include?(interface_name)
    next if interface_name.empty?
    next if !interface_name =~ /^ether[0-9]{1,2}/

    # Valid GW
    valid_gw = true if interface_gw =~ /^[0-9\.]+$/

    # Valid rt_table
    valid_rt_table = true if interface_rt_table =~ /^[0-9]+$/ and interface_rt_table.to_i >= 1000 and interface_rt_table.to_i <= 2000
    
    # Valid rt_mark
    valid_rt_mark = true if interface_rt_mark =~ /^[0-9]+$/ and interface_rt_mark.to_i >= 1000 and interface_rt_mark.to_i <= 2000

    wan_interfaces[interface_name] = { "rt_table" => interface_rt_table , "gw" => interface_gw , "rt_mark" => interface_rt_mark }
end

tmp_interfaces = File.readlines("#{my_dir}/lan_interfaces.list")

tmp_interfaces.each do |line|
    next if line =~ /^#/

    parts = line.strip.split
    next if parts.size < 1

    interface_name = parts[0].strip
    
    # Valid interface name
    next if !ether_interfaces_list.include?(interface_name)
    next if interface_name.empty?
    next if !interface_name =~ /^ether[0-9]{1,2}/

    lan_interfaces << interface_name
end

nftables_cmd="/usr/sbin/nft"
iptables_cmd="/sbin/iptables"
ip_cmd="/sbin/ip"

nft_vm_id="nft_vm"
if $use_nft_vm
    nft_vm_id="#{nft_vm_id}_#{rand(1000..2000)}"
    puts("USing nftables VM: #{nft_vm_id}")

    system_quietly("#{ip_cmd} netns del #{nft_vm_id}")
    commands << "#{ip_cmd} netns add #{nft_vm_id}"
    commands << "#{ip_cmd} netns exec #{nft_vm_id} #{ip_cmd} link set lo up"
    
    netns_exec="#{ip_cmd} netns exec #{nft_vm_id}"

    nftables_cmd="#{netns_exec} #{nftables_cmd}"
    iptables_cmd="#{netns_exec} #{iptables_cmd}"
    ip_cmd="#{netns_exec} #{ip_cmd}"
end

commands << "/bin/bash #{my_dir}/disable-rp-filter.sh"

# should be empty
vm_nftables=system_quietly("#{nftables_cmd} -nn list ruleset")["stdout"]

nftables_commands << "flush table lb_nat" if $flush_tables and !$use_nft_vm
nftables_commands << "delete table lb_nat" if $delete_tables and !$use_nft_vm

nftables_commands << "add table lb_nat"
nftables_commands << "add chain ip lb_nat postrouting { type nat hook postrouting priority 100; policy accept; }"
nftables_commands << "add rule lb_nat postrouting oifname { \"#{wan_interfaces.keys.join("\" , \"")}\" } counter masquerade"

# MANGLE
nftables_commands << "flush table iplb" if $flush_tables and !$use_nft_vm
nftables_commands << "delete table iplb" if $delete_tables  and !$use_nft_vm

nftables_commands << "add table lb_mangle"

nftables_commands << "add chain ip lb_mangle prerouting { type filter hook prerouting priority -150; policy accept; }"
nftables_commands << "add chain ip lb_mangle input { type filter hook input priority -150; policy accept; }"
nftables_commands << "add chain ip lb_mangle forward { type filter hook forward priority -150; policy accept; }"
nftables_commands << "add chain ip lb_mangle output { type route hook output priority -150; policy accept; }"
nftables_commands << "add chain ip lb_mangle postrouting { type filter hook postrouting priority -150; policy accept; }"


port_based_ip_protocols.each do |protocol|
    nftables_commands << "add chain ip lb_mangle PCC_OUT_#{protocol.upcase}"
end

nftables_commands << "add chain ip lb_mangle PCC_OUT_OTHERS"

# Creating tables per WAN interface for CT marking

wan_vmap_targets = []
int_counter=0
wan_interfaces.each_key do |interface|
    jump_table = ""
    case jump_format
    when "table"
        jump_table="wan_rt_table_#{wan_interfaces[interface]["rt_table"]}"
    when "mark"
        jump_table="wan_rt_mark_#{wan_interfaces[interface]["rt_mark"]}"
    else
        jump_table="wan_rt_table_#{wan_interfaces[interface]["rt_table"]}_rt_mark_#{wan_interfaces[interface]["rt_mark"]}"
    end
    nftables_commands << "add chain ip lb_mangle #{jump_table}"
    nftables_commands << "add rule ip lb_mangle #{jump_table} ct mark set 0x#{wan_interfaces[interface]["rt_mark"]} counter"

  wan_vmap_targets << "#{int_counter} : jump #{jump_table}"
  int_counter=int_counter+1
end

port_based_ip_protocols.each do |protocol|
  case $jhash_distribution
  when "srcip+dstip+dstport"
    nftables_commands << "add rule ip lb_mangle PCC_OUT_#{protocol.upcase} jhash ip protocol . ip saddr . ip daddr . #{protocol.downcase} dport mod #{int_counter} vmap { #{wan_vmap_targets.join(" , ")} } counter"
  when "srcip+dstip"
    nftables_commands << "add rule ip lb_mangle PCC_OUT_#{protocol.upcase} jhash ip protocol . ip saddr . ip daddr dport mod #{int_counter} vmap { #{wan_vmap_targets.join(" , ")} } counter"
  when "srcip"
    nftables_commands << "add rule ip lb_mangle PCC_OUT_#{protocol.upcase} jhash ip protocol . ip saddr mod #{int_counter} vmap { #{wan_vmap_targets.join(" , ")} } counter"
  else
    nftables_commands << "add rule ip lb_mangle PCC_OUT_#{protocol.upcase} jhash ip protocol . ip saddr . #{protocol.downcase} sport . ip daddr . #{protocol.downcase} dport mod #{int_counter} vmap { #{wan_vmap_targets.join(" , ")} } counter"
  end
end

nftables_commands << "add rule ip lb_mangle PCC_OUT_OTHERS ip protocol { \"#{port_based_ip_protocols.join("\" , \"")}\" } counter return"

nftables_commands << "add rule ip lb_mangle PCC_OUT_OTHERS jhash ip protocol . ip saddr . ip daddr mod #{int_counter} vmap { #{wan_vmap_targets.join(" , ")} } counter"

nftables_commands << "add chain ip lb_mangle SET_MARK_ON_PACKET"

nftables_commands << "add chain ip lb_mangle SET_MARK_ON_PACKET_NON_0"

nftables_commands << "add chain ip lb_mangle SET_MARK_ON_PACKET_NON_0_COUNTERS"

nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET meta mark set ct mark counter"

nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET ct mark != 0x0 counter"
nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET ct mark != 0x0 ct state new counter"
nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET ct mark != 0x0 ct state established,related counter"
nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET ct mark == 0x0 counter"
nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET ct mark == 0x0 ct state new counter"
nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET ct mark == 0x0 ct state established,related counter"
nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET counter"

nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET_NON_0 ct mark set mark counter"
nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET_NON_0 ct state new counter"
nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET_NON_0 ct state established counter"
nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET_NON_0 ct state related counter"
nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET_NON_0 counter"
nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET_NON_0 jump SET_MARK_ON_PACKET_NON_0_COUNTERS"

nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET_NON_0_COUNTERS ct state new counter"
nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET_NON_0_COUNTERS ct state established counter"
nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET_NON_0_COUNTERS ct state related counter"
nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET_NON_0_COUNTERS ct state invalid counter"
nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET_NON_0_COUNTERS ct state untracked counter"

nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET_NON_0_COUNTERS ct direction original counter"
nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET_NON_0_COUNTERS ct direction reply counter"

nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET_NON_0_COUNTERS ct status expected counter"
nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET_NON_0_COUNTERS ct status seen-reply counter"
nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET_NON_0_COUNTERS ct status assured counter"
nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET_NON_0_COUNTERS ct status confirmed counter"
nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET_NON_0_COUNTERS ct status snat counter"
nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET_NON_0_COUNTERS ct status dnat counter"
nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET_NON_0_COUNTERS ct status dying counter"

if $interfaces_counters
    ether_interfaces_list.each do |i| 

        counters_ip_protocols.each do |protocol|
            nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET_NON_0_COUNTERS iifname #{i} ip protocol #{protocol} counter"
        end
        
        nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET_NON_0_COUNTERS iifname #{i} ct state new counter"
        nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET_NON_0_COUNTERS iifname #{i} ct state established counter"
        nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET_NON_0_COUNTERS iifname #{i} ct state related counter"
        nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET_NON_0_COUNTERS iifname #{i} ct state invalid counter"
        nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET_NON_0_COUNTERS iifname #{i} ct state untracked counter"
        
        nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET_NON_0_COUNTERS iifname #{i} ct direction original counter"
        nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET_NON_0_COUNTERS iifname #{i} ct direction reply counter"
        
        nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET_NON_0_COUNTERS iifname #{i} ct status expected counter"
        nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET_NON_0_COUNTERS iifname #{i} ct status seen-reply counter"
        nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET_NON_0_COUNTERS iifname #{i} ct status assured counter"
        nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET_NON_0_COUNTERS iifname #{i} ct status confirmed counter"
        nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET_NON_0_COUNTERS iifname #{i} ct status snat counter"
        nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET_NON_0_COUNTERS iifname #{i} ct status dnat counter"
        nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET_NON_0_COUNTERS iifname #{i} ct status dying counter"
    end
end

nftables_commands << "add rule ip lb_mangle SET_MARK_ON_PACKET_NON_0_COUNTERS counter accept"

nftables_commands << "add rule ip lb_mangle prerouting jump SET_MARK_ON_PACKET"

nftables_commands << "add rule ip lb_mangle prerouting ct mark != 0x0 jump SET_MARK_ON_PACKET_NON_0"

# Attaching new connections from specific interfaces with their respectible rt_mark

wan_interfaces.each_key do |interface|
    jump_table = ""
    case jump_format
    when "table"
        jump_table="wan_rt_table_#{wan_interfaces[interface]["rt_table"]}"
    when "mark"
        jump_table="wan_rt_mark_#{wan_interfaces[interface]["rt_mark"]}"
    else
        jump_table="wan_rt_table_#{wan_interfaces[interface]["rt_table"]}_rt_mark_#{wan_interfaces[interface]["rt_mark"]}"
    end
    nftables_commands << "add rule ip lb_mangle prerouting iifname #{interface} ct state new ct mark == 0x0 counter jump #{jump_table}"
end

port_based_ip_protocols.each do |protocol|
    nftables_commands << "add rule ip lb_mangle prerouting iifname { \"#{lan_interfaces.join("\" , \"")}\" } ip protocol #{protocol.downcase} ct state new counter jump PCC_OUT_#{protocol.upcase}"
end

nftables_commands << "add rule ip lb_mangle prerouting iifname { \"#{lan_interfaces.join("\" , \"")}\" } ct state new counter jump PCC_OUT_OTHERS"

wan_interfaces.each_key do |interface|
    nftables_commands << "add rule ip lb_mangle prerouting ct mark 0x#{wan_interfaces[interface]["rt_mark"]} meta mark set 0x#{wan_interfaces[interface]["rt_mark"]} counter"
end

nftables_commands << "add chain ip lb_mangle POSTROUTING_COUNTERS"
nftables_commands << "add rule ip lb_mangle POSTROUTING_COUNTERS counter"

if $interfaces_counters
    ether_interfaces_list.each do |i| 
        counters_ip_protocols.each do |protocol|
            nftables_commands << "add rule ip lb_mangle POSTROUTING_COUNTERS oifname #{i} ip protocol #{protocol} counter"
        end

        nftables_commands << "add rule ip lb_mangle POSTROUTING_COUNTERS oifname #{i} ct state new counter"
        nftables_commands << "add rule ip lb_mangle POSTROUTING_COUNTERS oifname #{i} ct state established counter"
        nftables_commands << "add rule ip lb_mangle POSTROUTING_COUNTERS oifname #{i} ct state related counter"
        nftables_commands << "add rule ip lb_mangle POSTROUTING_COUNTERS oifname #{i} ct state invalid counter"
        nftables_commands << "add rule ip lb_mangle POSTROUTING_COUNTERS oifname #{i} ct state untracked counter"
        
        nftables_commands << "add rule ip lb_mangle POSTROUTING_COUNTERS oifname #{i} ct direction original counter"
        nftables_commands << "add rule ip lb_mangle POSTROUTING_COUNTERS oifname #{i} ct direction reply counter"
        
        nftables_commands << "add rule ip lb_mangle POSTROUTING_COUNTERS oifname #{i} ct status expected counter"
        nftables_commands << "add rule ip lb_mangle POSTROUTING_COUNTERS oifname #{i} ct status seen-reply counter"
        nftables_commands << "add rule ip lb_mangle POSTROUTING_COUNTERS oifname #{i} ct status assured counter"
        nftables_commands << "add rule ip lb_mangle POSTROUTING_COUNTERS oifname #{i} ct status confirmed counter"
        nftables_commands << "add rule ip lb_mangle POSTROUTING_COUNTERS oifname #{i} ct status snat counter"
        nftables_commands << "add rule ip lb_mangle POSTROUTING_COUNTERS oifname #{i} ct status dnat counter"
        nftables_commands << "add rule ip lb_mangle POSTROUTING_COUNTERS oifname #{i} ct status dying counter"

    end

end

nftables_commands << "add rule ip lb_mangle POSTROUTING_COUNTERS ct mark set mark counter"
nftables_commands << "add rule ip lb_mangle POSTROUTING_COUNTERS counter"

nftables_commands << "add rule ip lb_mangle postrouting counter jump POSTROUTING_COUNTERS"
nftables_commands << "add rule ip lb_mangle postrouting ct mark set mark counter"
nftables_commands << "add rule ip lb_mangle postrouting counter"

file = File.open("#{my_dir}/tmp.in.nft", "w")
file.puts("#!/usr/sbin/nft -f")
file.puts(nftables_commands.join("\n"))
file.close

commands << "#{nftables_cmd} -f #{my_dir}/tmp.in.nft"

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

puts("Dumping nftables ruleset:")
res = system_quietly("#{nftables_cmd} -nn list ruleset")

puts("Finsihed Dumping nftables ruleset!")

new_nft_ruleset=res["stdout"]


nftables_cmd=nftables_cmd.gsub("#{netns_exec}", "").strip
iptables_cmd=iptables_cmd.gsub("#{netns_exec}", "").strip
ip_cmd=ip_cmd.gsub("#{netns_exec}", "").strip

File.write("#{my_dir}/new-ruleset.nft", new_nft_ruleset.join)
if $use_nft_vm
  puts "Deleteing #{nft_vm_id} => \"#{ system_quietly("#{ip_cmd} netns del #{nft_vm_id}") }\""
end
puts "END OF RULES"

res = system_quietly("/bin/bash #{my_dir}/flush-all-rules.sh")
puts res["stdout"]
    

wan_interfaces.each_key do |interface|
    res = system_quietly("/bin/bash #{my_dir}/new-next-hop-table.sh #{wan_interfaces[interface]["rt_table"]} #{wan_interfaces[interface]["gw"]} #{wan_interfaces[interface]["rt_mark"]}")
    puts res["stdout"]
end

wan_interfaces.each_key do |interface|
    res = system_quietly("/bin/bash #{my_dir}/create-fw-mark-rule.sh #{wan_interfaces[interface]["rt_mark"]} #{wan_interfaces[interface]["rt_table"]}")
    # puts res["stdout"]
end

res = system_quietly("#{ip_cmd} rule show")
puts res["stdout"]