# CSCE 465 HW4 Docker conversation

> In the context of this assignment, what do i need to know about docker containers, dockerfiles, and compose files. I read a fair bit of documentation but i would still like you to explain it further to me. I know the assignment itself has a small example or template

**Assistant**

I’ll look for the assignment template so I can connect the Docker concepts to the files and commands you’re using.

For **CSCE 465 HW4**, think of Docker as a way to run three separate participants in a network experiment inside your Ubuntu VM. The **Dockerfile** describes what software those participants have available. The **Compose file** describes which participants exist, what each one runs, and how they connect. The **containers** are the actual instances you can inspect while the lab is running.

### 1. How can one Dockerfile serve three containers?

A Dockerfile builds an **image**, a reusable starting filesystem with software already installed. HW4 says one small image can serve all three containers. For example, you can start with the exact Python base-image tag given in the handout and install `curl` and `socat` during the build. All three containers then have those tools available. [Dockerfile documentation][dockerfile]

What makes the containers different is **which process each runs, which files it can see, and which IP address it gets**.

| Compose service | Lab address | What it represents |
|---|---|---|
| `agent-node` | `172.30.0.10` | The environment where the agent runs the mock skill and can access the fake token. |
| `web-lab` | `172.30.0.40:8000` | The web server that serves the two assignment HTML pages. |
| `mock-c2` | `172.30.0.66:8080` | The simulated receiver that stores the body of a request in `/data/received.bin`. |

For example, `web-lab` and `mock-c2` can both use Python from the same image. Compose can tell the first to start a static web server and the second to run `c2.py`. Each gets its own processes and writable filesystem. That means `/data/received.bin` belongs to the receiver container unless you explicitly mount storage there.

### 2. How to read the assignment’s Compose template

The example on pages 3–4 defines the **network**. Here is that portion with its indentation made visible:

```yaml
networks:
  hw4net:
    driver: bridge
    driver_opts:
      com.docker.network.bridge.name: br-hw4
    ipam:
      config:
        - subnet: 172.30.0.0/24
```

There are **three different names or values** here that matter for different reasons:

| Entry | What it means in HW4 |
|---|---|
| `hw4net` | The name you use **inside the Compose file** when attaching a service to this network. |
| `br-hw4` | The name of the **Linux bridge interface on your Ubuntu VM**. This gives you a predictable interface for packet capture and filtering. |
| `172.30.0.0/24` | The range of addresses on the lab network. The three fixed container IPs belong to this range. |

The part that is easy to miss is that **defining the subnet does not assign `.10`, `.40`, or `.66` to anyone**. That happens separately under each entry in `services`. For example, this fragment shows how the agent gets its address:

```yaml
services:
  agent-node:
    build: .
    networks:
      hw4net:
        ipv4_address: 172.30.0.10
```

Read that as “For the service named `agent-node`, build an image using this directory, attach the container to `hw4net`, and give it `172.30.0.10`.” The top-level `networks` section defines the network **once**. The `networks` section under a service tells Docker how **that container** joins it. Containers on the same Compose network can also reach each other by service name. [Docker Compose networking](https://docs.docker.com/compose/how-tos/networking/)

### 3. What happens when you run the lab?

| Command or instruction | When it acts | What it does |
|---|---|---|
| `RUN` in the Dockerfile | While building the image | Prepares the environment, such as installing `curl` and `socat`. |
| `command:` under a Compose service | When that container starts | Selects the process for that role, such as the web server. |
| `docker compose up -d --build` | From your Ubuntu VM | Builds the needed image, creates or updates the lab containers and network, and starts the services in the background. |
| `docker compose ps` | After startup | Shows the service containers and their current status. |
| `docker compose exec agent-node hostname` | While `agent-node` is running | Runs `hostname` **inside the existing agent container**. |

Two details matter for interpreting your results. First, a container stays running while its main process is alive. If `docker compose exec` says the service is not running, `docker compose ps -a` shows whether it exited, and `docker compose logs <service>` shows what its process printed. Second, files in your VM’s homework folder appear in a container only if you arrange for that. Dockerfile `COPY` puts a copy into the image at build time. A Compose bind mount makes a chosen host file or directory visible at runtime, and `:ro` makes that mount read-only inside the container. HW4 asks you to limit mounts to assignment files. [Dockerfile documentation][dockerfile]

You’ve already seen how this fits together in your packet capture. Your TShark output showed `172.30.0.10:54174` sending an HTTP `POST` to `172.30.0.66:8080`. **Compose tells you who those addresses belong to**: the agent and the receiver. `8080` is the receiver’s listening port from the lab topology. `54174` was the temporary source port chosen for that connection, so you wouldn’t put it in the Compose file. That’s the practical reason the assignment gives the containers fixed addresses and the bridge a fixed name. [HW4 handout, pp. 3–4](https://chatgpt.com/library?file_id=libfile_7e7818e1dab88191b0596348c6f4d5a8&account_id=personal)

> About read only, how do I ensure that is the case

**Assistant**

I’ll check how to set a mount read-only in Compose and verify it on the running container.

In your `docker-compose.yml`, add **`:ro`** to the end of each `volumes:` entry that the container only needs to read. For example, if `agent-node` expects the token at `/app/fake_secrets.txt`, use this mount. [Docker bind mounts][mounts]

```yaml
services:
  agent-node:
    volumes:
      - ./fake_secrets.txt:/app/fake_secrets.txt:ro
```

The left path is the file on your Ubuntu VM. The right path is where it appears inside `agent-node`. The `:ro` means the agent **can read the token but cannot modify the file through that mount**. You can still edit the original from the VM. [Docker bind mounts][mounts]

**For HW4**, use `:ro` for mounted inputs such as `mock_skill.sh`, `fake_secrets.txt`, the `web/` pages, and `c2.py`. Keep `mock-c2`’s `/data` directory writable so the receiver can save `received.bin`.

**To verify**, run these from your `hw4` directory after editing the Compose file. The first command applies the change. The second shows the actual mounts on `agent-node`.

```bash
docker compose up -d
docker inspect "$(docker compose ps -q agent-node)" \
  --format '{{range .Mounts}}{{println .Destination "writable=" .RW}}{{end}}'
```

For the example above, you should see **`/app/fake_secrets.txt writable= false`**. That confirms Docker applied the read-only setting. [Docker bind mounts][mounts]

> This is a file I have been working on but i keepp having issues as docker ps shows that the file instantly finishes once initiated

**Assistant**

I’ll check the startup command in your file to see what should keep the container running.

In your Compose file, `agent-node` runs `sleep infinity`, `web-lab` runs a Python web server, and `mock-c2` runs `c2.py`. The first two commands should keep their containers running. The third stays up only while `c2.py` is running. Your `:ro` mounts look correct.

**First, check which container actually exited.** From your `hw4` directory, run these using the Compose filename on your VM. If it’s named `docker-compose(1).yml`, use that name inside the quotes.

```bash
docker compose -f 'docker-compose.yml' ps -a
docker compose -f 'docker-compose.yml' logs --tail=30
```

- **`Up`** means the container is running. If `docker compose up -d` returned you to the terminal immediately, that’s expected.
- **`Exited (0)`** means the command finished successfully. If that’s `mock-c2`, check whether `c2.py` reaches `serve_forever()` when run as a script.
- **`Exited (1)`** means the command reported an error. Look for that service’s name in the logs and read the last error line.

If `ps -a` shows **no services**, paste the exact command you used to start the lab. Otherwise, paste the two outputs above so we can identify the cause.

> The problem might have to do with the skill

**Assistant**

If you mean `mock_skill.sh`, **the script can finish while `agent-node` keeps running**. In your Compose file, `command: ["sleep", "infinity"]` keeps `agent-node` alive. The `volumes:` line makes the script available at `/app/mock_skill.sh`. It doesn’t launch it.

If you started the lab with `docker compose up -d` and then ran the script with `docker compose exec`, returning to the prompt just means the script finished. Check the container itself with:

```bash
docker compose ps -a agent-node
```

If it says **`Up`**, the container is fine and we can focus on what the script did. If it says **`Exited`**, the exact launch command matters. For example, if you used `docker compose run agent-node ...` to run the script, Compose created a one-off container that exits when the script finishes.

Can you paste **the exact command you used to launch the skill** and the output of the status check above?

> Well the problem is that the skill should keep running but it just stops

**Assistant**

I’ll look for `mock_skill.sh` to check what happens when it reaches the end of the script.

I checked your `mock_skill.sh`. **The `&` at the end of the `socat` line is why the script returns to the prompt.** Bash starts the listener in the background, checks the `if` block, and reaches the end of the script. For this assignment, the **listener** is what should stay running. The shell script itself can finish.

`docker ps` shows containers. To see whether `socat` is still running **inside** `agent-node`, run this after the script returns:

```bash
docker compose top agent-node
```

- If you see **`sleep infinity` and `socat`**, the script finished and the listener process is still running.
- If you see **only `sleep infinity`**, the container is up but the listener stopped or failed to start.

If `socat` is missing, paste the exact command you used to run the script and any terminal output it printed.

> ive seen about keeping the process id while in the background how would that be done

**Assistant**

In Bash, **`$!` gives you the PID of the most recent background process**. Save it immediately after the line ending in `&`. Here’s a small example:

```bash
sleep 30 &
child_pid=$!
echo "Background PID: $child_pid"
wait "$child_pid"
```

The distinction for your script is that **`child_pid=$!` remembers the PID**, while **`wait "$child_pid"` keeps the script open until that process exits**. Saving the PID alone won’t keep either process running. If the background process stops immediately, `wait` returns immediately too, with that process’s exit status.

[dockerfile]: https://docs.docker.com/get-started/docker-concepts/building-images/writing-a-dockerfile/
[mounts]: https://docs.docker.com/engine/storage/bind-mounts/
