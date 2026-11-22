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
