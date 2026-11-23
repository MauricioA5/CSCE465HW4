# CSCE 465/765 Homework 4

## Task 0 — Lab Preparation

**Install Docker Engine and Compose in the course VM.**

```bash
sudo apt remove -y docker.io docker-compose docker-compose-v2 \
  containerd runc 2>/dev/null || true
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF_DOCKER
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF_DOCKER
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker "$USER"
```

**Install the packet tools and Suricata.**

```bash
sudo apt install -y nmap tcpdump tshark netcat-openbsd
sudo add-apt-repository -y ppa:oisf/suricata-stable
sudo apt update
sudo apt install -y suricata
sudo usermod -aG suricata "$USER"
```

**Log out and back in, then verify the tools.**

```bash
docker run --rm hello-world
docker compose version
nmap --version
tcpdump --version
tshark --version
suricata -V
```

## Task 1 — Build the local network lab

### 1.1 Output of `docker compose ps`

```bash
docker compose -p hw4 up -d --build
docker compose -p hw4 ps
```

### 1.2 Output of `docker network inspect`

```bash
docker network inspect hw4_hw4net
```

### 1.3 Baseline transfer verification

Compare hashes after the baseline transfer.

```bash
sha256sum fake_secrets.txt
docker compose -p hw4 exec mock-c2 sha256sum /data/received.bin
```

### 1.4 Role of each container

- `web-lab` serves the benign and adversarial pages.
- `agent-node` runs the mock skill and holds the fake token.
- `mock-c2` receives the POST body.

[Task 1 evidence](evidence/task1/)

## Task 2 — Scan, capture, and reconstruct the event

### 2.1 Scan output

```bash
nmap -sT -p 1-10000 172.30.0.10
```

### 2.2 Reconstruction items

Separate captures are needed for each of the runs. Stop packet captures with Ctrl+C.

```bash
# Incident capture
sudo tcpdump -i br-hw4 -s 0 -w hw4-malicious.pcap 'net 172.30.0.0/24'
```

```bash
# Clean capture
sudo tcpdump -i br-hw4 -s 0 -w hw4-clean.pcap 'net 172.30.0.0/24'
```

```bash
# Clean request, in a second terminal
docker compose -p hw4 exec agent-node curl -s http://172.30.0.40:8000/benign.html
```

```bash
# POST connection details
tshark -r hw4-malicious.pcap -Y 'http.request.method == "POST"' \
  -T fields -e ip.src -e tcp.srcport -e ip.dst -e tcp.dstport \
  -e tcp.stream -e http.request.method -e http.request.uri
```

```bash
# Token and timestamps (stream 1 in the saved run)
tshark -r hw4-malicious.pcap -q -z follow,tcp,ascii,1
tshark -r hw4-malicious.pcap -Y 'tcp.stream == 1' \
  -T fields -e frame.number -e frame.time | sed -n '1p;$p'
```

```bash
# POST body and original file hashes
tshark -r hw4-malicious.pcap -Y 'http.request.method == "POST"' \
  -T fields -e http.file_data | xxd -r -p | sha256sum
sha256sum fake_secrets.txt
```

### 2.3 Sequence of events demonstrated by the capture

```bash
tshark -r hw4-malicious.pcap -Y http
tshark -r hw4-clean.pcap -Y http
```

[Task 2 evidence](evidence/task2/)

## Task 3 — Egress firewall

### 3.1 Apply and remove the firewall

`firewall.sh` enables `br_netfilter` so traffic between containers on the same bridge passes through iptables, then appends the policy rules to the `DOCKER-USER` chain. `firewall-reset.sh` deletes those rules.

```bash
sudo bash firewall.sh
sudo bash firewall-reset.sh
```

### 3.2 Rules and the policy each one enforces

| #   | Rule                                                                      | Policy                                            |
| --- | ------------------------------------------------------------------------- | ------------------------------------------------- |
| 1   | Accept `ESTABLISHED,RELATED`                                              | Allow return traffic for permitted connections    |
| 2   | Accept TCP `172.30.0.10` → `172.30.0.40:8000`                             | agent-node may fetch pages from web-lab           |
| 3   | Log (`HW4-C2-DROP: `) and drop NEW TCP `172.30.0.10` → `172.30.0.66:8080` | Block and record exfiltration attempts to mock-c2 |
| 4   | Drop any other NEW connection from `172.30.0.10`                          | Default-deny for agent-node egress                |
| 5   | `RETURN`                                                                  | Leave unrelated Docker traffic unchanged          |

### 3.3 Verification tests

```bash
# Clear the old upload so a new one would be visible
docker compose -p hw4 exec mock-c2 rm -f /data/received.bin

# 1. Benign fetch is allowed (expect HTTP 200)
docker compose -p hw4 exec agent-node curl -s -o /dev/null -w '%{http_code}\n' http://172.30.0.40:8000/benign.html

# 2. Exfiltration is blocked (expect a hang; press Ctrl+C, no new received.bin)
docker compose -p hw4 exec agent-node bash /app/mock_skill.sh exfiltrate-course-file
docker compose -p hw4 exec mock-c2 ls -l /data/received.bin

# 3. Other egress is dropped (expect a timeout, not "Connection refused")
docker compose -p hw4 exec agent-node curl --max-time 5 http://172.30.0.40:8080/

# 4. Inbound to the mock skill still works (expect the banner)
nc 172.30.0.10 9009

# 5. Other containers are unaffected (expect HTTP 204)
docker compose -p hw4 exec web-lab curl -s -o /dev/null -w '%{http_code}\n' -X POST http://172.30.0.66:8080/
```

### 3.4 Counters and log lines

```bash
sudo iptables -L DOCKER-USER -v -n --line-numbers
sudo dmesg | grep HW4-C2-DROP
```

[Task 3 evidence](evidence/task3/)

## Task 4 — Suricata detection rules

### 4.1 Rules in `local.rules`

| SID     | Message                  | Detects                                                                         |
| ------- | ------------------------ | ------------------------------------------------------------------------------- |
| 1000001 | Fake Secret Exfiltration | The fake token in the HTTP POST body from agent-node to mock-c2:8080            |
| 1000002 | Course Marker Detecter   | The `CSCE465-COURSE-MARKER` injection marker in the page served by web-lab:8000 |
| 1000003 | TCP Connection Detecter  | Any TCP connection from agent-node to mock-c2:8080                              |

### 4.2 Run Suricata against the Task 2 captures

Both captures were recorded before the firewall existed. `-k none` disables checksum validation, since packets captured on the Docker bridge otherwise get discarded.

```bash
mkdir -p suricata-malicious suricata-clean
suricata -r hw4-malicious.pcap -S local.rules -k none -l suricata-malicious
suricata -r hw4-clean.pcap -S local.rules -k none -l suricata-clean
cat suricata-malicious/fast.log
cat suricata-clean/fast.log
```

Expected: all three rules alert on the malicious capture, and none alert on the clean capture.

[Task 4 evidence](evidence/task4/)
