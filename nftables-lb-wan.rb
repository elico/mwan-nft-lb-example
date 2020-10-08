#!/usr/bin/env ruby

my_dir = __dir__

$flush_tables = true

wan_interfaces = {}

lan_interfaces = [ "ether23" ]

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


("05".."15").each do |i| 
    wan_interfaces["ether#{i.gsub(/^0/, "")}"] = { "rt_table" => gen_rt_table("ether#{i.gsub(/^0/, "")}"), "gw" => "192.168.2#{i}.254" , "rt_mark" => gen_rt_mark("ether#{i.gsub(/^0/, "")}") }
end

nftables_cmd="/usr/sbin/nft"
iptables_cmd="/sbin/iptables"
ip_cmd="/sbin/ip"


`/bin/bash #{my_dir}/disable-rp-filter.sh`

wan_interfaces.each_key do |interface|
    puts `/bin/bash #{my_dir}/new-next-hop-table.sh #{wan_interfaces[interface]["rt_table"]} #{wan_interfaces[interface]["gw"]}`
end

`#{nftables_cmd} flush table nat` if $flush_tables

`#{nftables_cmd} add table nat`
`#{nftables_cmd} add chain ip nat postrouting '{ type nat hook postrouting priority 100; policy accept; }'`
`#{nftables_cmd} add rule nat postrouting counter oifname { \"#{wan_interfaces.keys.join("\" , \"")}\" } masquerade`


# MANGLE
`#{nftables_cmd} flush table mangle` if $flush_tables

`#{nftables_cmd} add table mangle`

`#{nftables_cmd} add chain ip mangle prerouting '{ type filter hook prerouting priority -150; policy accept; }'`
`#{nftables_cmd} add chain ip mangle input '{ type filter hook input priority -150; policy accept; }'`
`#{nftables_cmd} add chain ip mangle forward '{ type filter hook forward priority -150; policy accept; }'`
`#{nftables_cmd} add chain ip mangle output '{ type route hook output priority -150; policy accept; }'`
`#{nftables_cmd} add chain ip mangle postrouting '{ type filter hook postrouting priority -150; policy accept; }'`


`#{nftables_cmd} add chain ip mangle PCC_OUT_TCP`
`#{nftables_cmd} add chain ip mangle PCC_OUT_UDP`
`#{nftables_cmd} add chain ip mangle PCC_OUT_OTHERS`

wan_vmap_targets = []
int_counter=0
wan_interfaces.each_key do |interface|
  `#{nftables_cmd} add chain ip mangle wan_rt_table_#{wan_interfaces[interface]["rt_table"]}`
  `#{nftables_cmd} add rule ip mangle wan_rt_table_#{wan_interfaces[interface]["rt_table"]} counter ct mark set 0x#{wan_interfaces[interface]["rt_mark"]}`
  wan_vmap_targets << "#{int_counter} : jump wan_rt_table_#{wan_interfaces[interface]["rt_table"]}"
  int_counter=int_counter+1
end

`#{nftables_cmd} add rule ip mangle PCC_OUT_TCP counter jhash ip saddr . tcp sport . ip daddr . tcp dport mod #{int_counter} vmap { #{wan_vmap_targets.join(" , ")} }`
`#{nftables_cmd} add rule ip mangle PCC_OUT_UDP counter jhash ip saddr . udp sport . ip daddr . udp dport mod #{int_counter} vmap { #{wan_vmap_targets.join(" , ")} }`

`#{nftables_cmd} add rule ip mangle PCC_OUT_OTHERS counter ip protocol { tcp, udp }  return`
`#{nftables_cmd} add rule ip mangle PCC_OUT_OTHERS counter jhash ip saddr . ip daddr mod #{int_counter} vmap { #{wan_vmap_targets.join(" , ")} }`

`#{nftables_cmd} add rule ip mangle prerouting counter meta mark set ct mark`

`#{nftables_cmd} add rule ip mangle prerouting ct mark != 0x0 counter ct mark set mark`
`#{nftables_cmd} add rule ip mangle prerouting iifname { \"#{lan_interfaces.join("\" , \"")}\" } ip protocol tcp ct state new counter jump PCC_OUT_TCP`
`#{nftables_cmd} add rule ip mangle prerouting iifname { \"#{lan_interfaces.join("\" , \"")}\" } ip protocol udp ct state new counter jump PCC_OUT_UDP`
`#{nftables_cmd} add rule ip mangle prerouting iifname { \"#{lan_interfaces.join("\" , \"")}\" } ct state new counter jump PCC_OUT_OTHERS`


wan_interfaces.each_key do |interface|
    `#{nftables_cmd} add rule ip mangle prerouting ct mark 0x#{wan_interfaces[interface]["rt_mark"]} counter meta mark set 0x#{wan_interfaces[interface]["rt_mark"]}`
end

`#{nftables_cmd} add rule ip mangle postrouting counter ct mark set mark`

`/bin/bash #{my_dir}/flush-all-rules.sh`

wan_interfaces.each_key do |interface|
    `/bin/bash #{my_dir}/create-fw-mark-rule.sh #{wan_interfaces[interface]["rt_mark"]} #{wan_interfaces[interface]["rt_table"]}`
end