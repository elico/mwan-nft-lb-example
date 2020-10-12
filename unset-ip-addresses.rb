#!/usr/bin/env ruby

("05".."15").each do |link|
  puts `nmcli connection modify ether#{link.to_s.gsub(/^0/, "")} ipv4.address "" ipv4.method disabled ipv6.method ignore autoconnect yes`
  puts `nmcli connection up ether#{link.to_s.gsub(/^0/, "")}`
end
puts `nmcli connection modify ether23 ipv4.address "" ipv4.method disabled ipv6.method ignore autoconnect yes`
puts `nmcli connection up ether23`
