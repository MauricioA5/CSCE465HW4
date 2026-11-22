modprobe br_netfilter
sysctl -w net.bridge.bridge-nf-call-iptables=1
# 1. Allow established and related return traffic
iptables -A DOCKER-USER -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
# 2. Allow agent-node to initiate TCP connections to web-lab on port 8000
iptables -A DOCKER-USER -p tcp -s 172.30.0.10 -d 172.30.0.40 --dport 8000 -j ACCEPT
# 3. Log and drop new connections from agent-node to mock-c2
iptables -A DOCKER-USER -s 172.30.0.10 -d 172.30.0.66 -p tcp --dport 8080 -m conntrack --ctstate NEW -j LOG --log-prefix "HW4-C2-DROP: "
iptables -A DOCKER-USER -s 172.30.0.10 -d 172.30.0.66 -p tcp --dport 8080 -m conntrack --ctstate NEW -j DROP
# 4. Drop other new forwarded connections from agent-node
iptables -A DOCKER-USER -s 172.30.0.10 -m conntrack --ctstate NEW -j DROP
# 5. Leave unrelated Docker traffic unchanged
iptables -A DOCKER-USER -j RETURN
