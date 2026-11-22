# CSCE 465 HW4 — Task 2 conversation

> In the context of task 2. I am having trouble figuring out how to gather evidence. Can you help me in learning / becoming experienced with the tools i am supposed to be using.
> Show me examples and please include references to proper documentation so i could double check if needed. Please keep it in the scope of task2 though as to not do too much

**AI response**

For Task 2, use **Nmap** to show where the listener is open, **tcpdump** to record what happens, and **TShark** to answer questions about that recording. Run the commands below from `~/csce465-agentsec/hw4` on your Ubuntu VM. The assignment’s Task 2 instructions are on page 5. [HW4-2.pdf](https://chatgpt.com/library?file_id=libfile_7e7818e1dab88191b0596348c6f4d5a8&account_id=personal)

### 1. Nmap — is the listener reachable?

With your mock skill running on `agent-node` in its no-argument mode, run this from the **VM host**:

```bash
nmap -n -p 9009 172.30.0.10
```

Look for `9009/tcp open`. That tells you the agent accepted a connection on that port. If you get `closed`, the listener was not accepting connections when you scanned. The `-p 9009` option selects the port, and the single IP limits the scan to `agent-node`. [Nmap documentation][nmap]

### 2. tcpdump — record the two runs separately

**Terminal 1** records traffic. Start it before doing anything in Terminal 2. If you already have a capture you want to keep, use a fresh filename because `-w` overwrites the file. [tcpdump manual][tcpdump]

```bash
sudo tcpdump -i br-hw4 -s 0 -w hw4-malicious.pcap 'net 172.30.0.0/24'
```

`-i br-hw4` selects the lab bridge, `-s 0` captures enough of each packet to retain the small HTTP body, and `-w` saves the packets. Wait for `listening on br-hw4`. [tcpdump manual][tcpdump]

**Terminal 2** performs the handout’s two incident actions in order. First fetch the page from the agent, then run the Task 2 mock-skill trigger as directed on page 5. When both actions finish, press **Ctrl-C in Terminal 1**.

```bash
docker compose exec agent-node curl -sS http://172.30.0.40:8000/adversarial.html
```

For the **clean capture**, repeat the Terminal 1 command with `-w hw4-clean.pcap`. In Terminal 2, run only the following command, then stop Terminal 1 with **Ctrl-C**.

```bash
docker compose exec agent-node curl -sS http://172.30.0.40:8000/benign.html
```

### 3. TShark — read the evidence

**Start with the HTTP requests.** This one command gives you the sequence, both endpoints, the method, the URI, and the TCP stream number. Read the options as a sentence: `-r` opens the recording, `-Y` selects matching packets, and each `-e` chooses a column to print. [TShark manual][tshark] · [HTTP field reference][http]

```bash
tshark -r hw4-malicious.pcap -Y 'http.request' -T fields -E header=y \
  -e frame.number -e ip.src -e tcp.srcport -e ip.dst -e tcp.dstport \
  -e http.request.method -e http.request.uri -e tcp.stream
```

Read the rows in frame order. You’re looking for the `GET /adversarial.html` going to `172.30.0.40:8000`, followed by the `POST /` going to `172.30.0.66:8080`. Together with the Nmap output, this explains the listener distinction: **the web request goes to `.40:8000`, the POST goes to `.66:8080`, and the open listener is on `.10:9009`.** Run the same command against `hw4-clean.pcap` to check that its only HTTP request is `GET /benign.html`.

**Use the POST row to choose the stream.** For example, if its `tcp.stream` column says `1`, run the commands below. Substitute your actual number. The first command shows the fake token in context. The second lists every captured packet in that connection, including the handshake and closing packets. Its first and last rows give the required timestamps in Unix epoch seconds. [TShark manual][tshark]

```bash
stream=1
tshark -r hw4-malicious.pcap -q -z "follow,tcp,ascii,$stream"

tshark -r hw4-malicious.pcap -Y "tcp.stream == $stream" \
  -T fields -e frame.number -e frame.time_epoch
```

**Hash the exact POST body.** For the handout’s TShark 4.2 setup, `http.file_data` is displayed as hex. This example selects the POST, decodes its hex into the original bytes, and hashes them. First check that the first command prints a nonempty value. An empty pipeline can still produce a valid-looking SHA-256 hash. [TShark manual][tshark] · [HTTP field reference][http]

```bash
body_hex=$(tshark -r hw4-malicious.pcap \
  -Y "tcp.stream == $stream && http.request.method == \"POST\"" \
  -T fields -e http.file_data)

printf '%s\n' "$body_hex"
if [ -n "$body_hex" ]; then
  printf '%s' "$body_hex" | tr -d ':' | xxd -r -p | sha256sum
  sha256sum fake_secrets.txt
fi
```

The **first hash** comes from the bytes you captured on the network. The **second hash** comes from your original fake-token file. Matching values show that the captured POST carried the exact contents of that file.

---

> for the reconstruction specifically what would i need to run

**AI response**

Run these in **one terminal on the Ubuntu VM**, in the folder containing `hw4-malicious.pcap`.

**1. Get the source and destination IPs and ports, HTTP method, URI, and TCP stream number.**

```bash
tshark -r hw4-malicious.pcap -Y 'http.request' -T fields -E header=y \
  -e frame.number -e ip.src -e tcp.srcport -e ip.dst -e tcp.dstport \
  -e http.request.method -e http.request.uri -e tcp.stream
```

Find the `POST` row. The last column is its stream number. Your earlier output showed `1`, so the commands below use `stream=1`. Change it if this capture shows a different number.

**2. Show the fake token in the POST body.**

```bash
stream=1
tshark -r hw4-malicious.pcap -q -z "follow,tcp,ascii,$stream"
```

Look directly below the POST headers for `CSCE465-FAKE-TOKEN-...`.

**3. Get the first and last packet timestamps for that entire TCP connection.**

```bash
tshark -r hw4-malicious.pcap -Y "tcp.stream == $stream" \
  -T fields -e frame.number -e frame.time | sed -n '1p;$p'
```

The first row is the start of the stream. The second is the end.

**4. Hash the exact POST body bytes.** On the assignment’s TShark 4.2 setup, `http.file_data` prints hex. This decodes it before hashing.

```bash
body_hex=$(tshark -r hw4-malicious.pcap \
  -Y "tcp.stream == $stream && http.request.method == \"POST\"" \
  -T fields -e http.file_data)

if [ -n "$body_hex" ]; then
  printf '%s' "$body_hex" | tr -d ':' | xxd -r -p | sha256sum
  sha256sum fake_secrets.txt
else
  echo "No POST body found. Check the stream number from step 1."
fi
```

The first hash is from the capture, and the second is from your file. They should match.

For the **separate-listener evidence**, pair your Nmap result showing `172.30.0.10:9009` open with step 1’s destination columns showing the GET going to `172.30.0.40:8000` and the POST going to `172.30.0.66:8080`.

---

> explain to me a bit more about packet capture and about this task in general, I wish to understand it more

**AI response**

Think of Task 2 as answering three questions: **What was listening? What crossed the network? What evidence connects those observations?**

### What is a packet capture?

When `agent-node` fetches a web page or sends a file, the exchange travels across the network as a series of **packets**. Each packet carries addressing information, and some also carry application data, such as an HTTP request or part of its body.

In your lab, `br-hw4` is the virtual bridge connecting the three containers. While `tcpdump` is running on that bridge, it records the packets it sees and their timestamps in a **PCAP file**. You can stop the capture and use TShark to examine that same recording as many times as you want. That’s why the order matters: start `tcpdump`, perform the lab actions, then stop it. [tcpdump manual][tcpdump] · [TShark manual][tshark]

### What does one line of your output actually tell you?

Take the POST row you saw earlier:

```text
172.30.0.10    54174    172.30.0.66    8080    1    POST    /
```

Read it as a sentence: **The agent at `172.30.0.10` used its local port `54174` to send an HTTP `POST` to the path `/` on `172.30.0.66:8080`. TShark labeled that TCP connection stream `1`.**

Two details make the rest of the task easier to understand:

- **Why are there two ports?** Each end of the connection has one. The agent used `54174` as a temporary port for this outgoing connection. The receiver was listening on `8080`. When the receiver replies, those roles reverse in the packet listing: the reply goes **from `8080` to `54174`**.
- **Why do you need the stream number?** The POST row shows one event within a longer conversation. Stream `1` groups the packets for that connection in **both directions**. Following it lets you read the POST headers, its body, and the server’s response together. Filtering on the whole stream also gives you the connection’s first and last captured packets. [TShark manual][tshark]

### How the pieces of Task 2 fit together

| Question | Evidence | What you learn |
|---|---|---|
| Was an unexpected service reachable? | Nmap shows `172.30.0.10:9009` open. | The agent was accepting incoming connections on `9009`. |
| What did the agent fetch first? | The capture shows a `GET /adversarial.html` going to `172.30.0.40:8000`. | The agent requested the adversarial page from `web-lab`. |
| What did the agent send afterward? | The POST stream goes to `172.30.0.66:8080`, and its body contains the fake token. | You can identify the destination **and** read the data sent because the lab uses plaintext HTTP. |
| Was it the exact file content? | The SHA-256 hash of the captured POST body matches the hash of `fake_secrets.txt`. | The captured bytes match the original file, including details such as whether it ends with a newline. |
| What does normal activity look like? | The clean capture shows `GET /benign.html` and its response. | You have a comparison run with an ordinary page fetch and no POST to `mock-c2`. |

The important distinction in your output is **`9009` versus `54174`**. Both belong to the agent, but they serve different purposes. `9009` is where the agent **accepts incoming connections**. `54174` is what it used to **send this particular POST**. That’s how the scan and capture fit together: the scan establishes that an extra listener existed, while the capture independently shows how the fake token actually traveled.

---

> format this conversation as a markdown file
> differentiating user input from AI response
> let user input be denoted with >

[nmap]: https://nmap.org/book/man-port-specification.html
[tcpdump]: https://manpages.ubuntu.com/manpages/noble/man8/tcpdump.8.html
[tshark]: https://www.wireshark.org/docs/man-pages/tshark.html
[http]: https://www.wireshark.org/docs/dfref/h/http.html
