#!/usr/bin/env ruby

require 'socket'

socket = TCPSocket.new('192.168.101.254', 50007)

puts socket.gets
socket.close
