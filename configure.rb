#!/usr/bin/ruby

require 'net/ssh'

def num_cpu(type)
	case type
	when "t2.medium", "t2.large", "m4.large", "m3.large"
		2
	when "m4.xlarge", "m3.xlarge"
		4
	when "m4.2xlarge", "m3.2xlarge"
		8
	when "m4.4xlarge"
		16
	when "m4.10xlarge"
		40
	else
		1
	end
end

print "1. Collecting server information from EC2... "
instances = {}
for line in `ec2-describe-instances`.split("\n").collect{ |x| x.strip.split("\t") }
	case line.first
	when "INSTANCE"
		instances[line[1]] = {:name => "", :type => line[9], :dns => line[3], :public_ip => line[16], :private_ip => line[17], :state => line[5]} if line[5] != "terminated"
	when "TAG"
		instances[line[2]][:name] = line[4] if line[3] == "Name" and instances.include? line[2]
	end
end
puts "#{instances.length} instances found!"
puts ""

# Group instances
server = instances.values.find{ |x| x[:name] == "server" }
controller = instances.values.find{ |x| x[:name] == "controller" }
clients = instances.values.select{ |x| x[:name].empty? }
all_hosts = [server, controller] + clients

# Assign aliases to instances
server[:alias] = "server"
controller[:alias] = "tsung0"
clients.each_with_index{ |x, i| x[:alias] = "tsung#{i+1}" }

# Build up /etc/hosts file
hosts = "127.0.0.1 localhost\n"
for x in all_hosts
	hosts += "#{x[:private_ip]} #{x[:alias]}\n"
end
hosts += <<END

# The following lines are desirable for IPv6 capable hosts
::1 ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
ff02::3 ip6-allhosts
END

# Copy /etc/hosts to each client
puts "2. Copying /etc/hosts to clients:"
File.open("etc_hosts", 'w') { |file| file.write(hosts) }
for x in all_hosts
	if x[:public_ip].empty?
		puts "   #{x[:alias]} Skipped! (No Public IP assigned)"
		next
	end
	`scp etc_hosts #{x[:dns]}:~`
	Net::SSH.start(x[:dns]){ |ssh| ssh.exec!("sudo mv etc_hosts /etc/hosts") }
	puts "   #{x[:alias]} Done!"
end
`rm etc_hosts`
puts ""

# Dump everything to console
puts "3. Generating final output:"
puts ""
puts "====================================== SUMMARY ======================================"
puts ""
for x in all_hosts
	printf "%-15s %-12s %-16s %-16s %s\n", x[:alias], x[:type], x[:private_ip], x[:public_ip], x[:state]
end
puts "\n"

puts "=================================== .tsung config ==================================="
puts ""
puts "  <clients>"
for x in [controller] + clients
	puts %Q{    <client host="#{x[:alias]}" cpu="#{num_cpu(x[:type])}" use_controller_vm="false" maxusers="50000" />}
end
puts "  </clients>"
puts "\n"

puts "===================================== /etc/hosts ===================================="
puts ""
puts hosts
puts "\n"