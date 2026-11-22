# 1. Remove rule: Allow established and related return traffic
iptables -D DOCKER-USER -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
# 2. Remove rule: Allow agent-node to initiate TCP connections to web-lab on port 8000
iptables -D DOCKER-USER -p tcp -s 172.30.0.10 -d 172.30.0.40 --dport 8000 -j ACCEPT
# 3. Remove rule: Log and drop new connections from agent-node to mock-c2
iptables -D DOCKER-USER -s 172.30.0.10 -d 172.30.0.66 -p tcp --dport 8080 -m conntrack --ctstate NEW -j LOG --log-prefix "HW4-C2-DROP: "
iptables -D DOCKER-USER -s 172.30.0.10 -d 172.30.0.66 -p tcp --dport 8080 -m conntrack --ctstate NEW -j DROP
# 4. Remove rule: Drop other new forwarded connections from agent-node
iptables -D DOCKER-USER -s 172.30.0.10 -m conntrack --ctstate NEW -j DROP
# 5. Remove rule: Leave unrelated Docker traffic unchanged
iptables -D DOCKER-USER -j RETURN