#!/usr/bin/env ruby

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


wan_interfaces = {}

("05".."15").each do |i| 
  wan_interfaces["ether#{i.gsub(/^0/, "")}"] = { "rt_table" => gen_rt_table("ether#{i.gsub(/^0/, "")}"), "gw" => "192.168.2#{i}.254" , "rt_mark" => gen_rt_mark("ether#{i.gsub(/^0/, "")}") }
end


wan_interfaces.each_key do |interface|
  puts("#{interface} #{wan_interfaces[interface]["gw"]} #{wan_interfaces[interface]["rt_table"]} #{wan_interfaces[interface]["rt_mark"]} ")
end
