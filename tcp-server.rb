#!/usr/bin.env ruby

require 'socket'


puts "Starting the Server..................."
server = TCPServer.new 50007 # Server bound to port 53492

$out = false

loop do
  Thread.start(server.accept) do |client|
    sock_domain, remote_port, remote_hostname, remote_ip = client.peeraddr
    client.puts("Client address = #{remote_ip}:#{remote_port}")
    line = client.gets
     $out = true if line =~ /exit/i
   begin
  #  How to get the request IP adress here
    rescue Errno::EPIPE
      puts "Connection broke!"    
    end
  end
  exit 0 if $out
end


