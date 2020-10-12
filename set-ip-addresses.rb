#!/usr/bin/env ruby

("05".."15").each do |link|
  puts `nmcli connection modify ether#{link.to_s.gsub(/^0/, "")} ipv4.addresses 192.168.2#{link}.100/24 ipv4.method manual autoconnect yes`
  puts `nmcli connection up ether#{link.to_s.gsub(/^0/, "")}`
end
puts `nmcli connection modify ether23 ipv4.addresses 192.168.125.254/24 ipv4.method manual autoconnect yes`
puts `nmcli connection up ether23`
