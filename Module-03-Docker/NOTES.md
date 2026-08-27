# Module 03 — Docker Notes

## M03-P01 — Container Fundamentals
Image = blueprint (read-only, not running). Container = running instance
of an image. Namespaces isolate what a process can *see* (PID, network,
filesystem). Cgroups limit what it can *use* (CPU, RAM, disk). Containers
share the host's kernel — no separate OS to boot — which is why they
start in milliseconds vs a VM's 30-60 second boot.

## M03-P02 — Install & Verify Docker
`docker --version` confirms install. `docker run <image>` pulls from
Docker Hub if not found locally, creates + starts a container, streams
output. Container exits when its main process finishes — exit code 0 =
success. `docker ps` shows running containers only; `docker ps -a` shows
all (including stopped). `docker container prune` removes all stopped
containers at once — good habit to avoid disk clutter over time.

Docker has two parts: the daemon (`dockerd`, background service that
does the actual work) and the client (`docker` command, just a
messenger that talks to the daemon over a socket). `systemctl status
docker` shows the daemon is running.

## M03-P03 — Images vs Containers vs Layers
An image is built from multiple stacked layers, not one solid block.
Each Dockerfile instruction creates a new layer (a diff from the layer
below). Docker caches layers — if dependencies are installed early and
app code is copied later, changing only the app code means only that
layer (and anything after it) rebuilds; the cached dependency layer is
reused. This makes CI/CD builds much faster.



## M03-P04 — Writing a Dockerfile
`FROM` sets the base image (e.g. `python:3.11-slim`) as the first layer.
`WORKDIR /app` sets the working directory inside the image's own
filesystem — separate from the host EC2's filesystem entirely; nothing
from the host exists in the image unless explicitly COPYed or mounted.
`COPY requirements.txt .` then `RUN pip install -r requirements.txt`
happens BEFORE `COPY app.py .` — dependencies rarely change (cached
layer, reused), app code changes often (only that layer rebuilds).
`RUN` executes at BUILD time, bakes result into image layer. `CMD`
does NOT run at build time — only recorded, executes later at
`docker run` (container start time).

Full Dockerfile:
```
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY app.py .
CMD ["python3", "app.py"]
```



## M03-P05 — Build, Tag, and Run Your Custom Image
`docker build -t my-first-app .` — `-t my-first-app` names/tags the
resulting image. The trailing `.` is the build context: tells Docker
to look in the current folder for the Dockerfile and any files it
needs to COPY in (requirements.txt, app.py).

Rebuild with zero changes: every step showed CACHED, near-instant.
Rebuild after only changing app.py: steps 1-4 (FROM, WORKDIR, COPY
requirements.txt, RUN pip install) stayed CACHED, only step 5 (COPY
app.py) re-ran. Proves Docker only rebuilds layers from the point of
change onward, reusing everything before it. Confirms the caching
theory from P03 with a live test.

`docker run <image-name>` starts a container from the image.
Container exits after the script finishes (same exit code convention
as before). `docker ps -a` to see stopped containers, `docker
container prune` to clean them up.



## M03-P06 — Container Networking (Bridge, Port Mapping)
Containers get their own private network namespace — own internal IP,
completely separate from the host EC2's IP. Analogy: EC2 = apartment
building with its own front door (EC2's own IP/localhost). Container =
an apartment inside, with its own separate door (container's internal
IP). A process inside the container (e.g. Flask) only listens on the
container's own door — never the building's front door — so
`curl http://localhost:5000` from the EC2 itself fails: nothing is
listening at the EC2's own address on that port, even though Flask is
running fine inside its container.

`-p HOST_PORT:CONTAINER_PORT` (e.g. `-p 8080:5000`) acts like a
doorman: forwards traffic hitting HOST_PORT on the EC2's real address
into CONTAINER_PORT inside the container's private network.

App must bind to `0.0.0.0` (all interfaces), not `127.0.0.1`
(localhost-only) — otherwise even correct `-p` mapping won't reach it,
since the app itself would refuse traffic arriving from "outside."

Reaching a containerized app from outside requires 3 aligned layers:
1. App binds to 0.0.0.0
2. Docker `-p` port mapping exists
3. AWS Security Group allows inbound traffic on the host port
Missing any one = same symptom ("connection refused"), different root
cause — useful checklist for real debugging.

`docker run -d` = detached mode, runs container in background so it
keeps serving requests instead of blocking the terminal.



## M03-P07 — Volumes & Bind Mounts (Persisting Data)
A container's own filesystem is temporary — exists only as long as the
container exists. Delete the container (`docker rm`), and anything
written inside it (logs, uploads, database files) is gone permanently.
Proved live: a log file written inside a container vanished completely
("No such file or directory") after `docker rm` + new container from
the same image.

Bind mount (`-v HOST_PATH:CONTAINER_PATH`, e.g.
`-v ~/docker-lab-02/logs:/app/logs`) fixes this — data physically lives
on the EC2's own disk at a path YOU choose and can browse/edit directly.
Proved live: same log file survived intact after `docker rm` + new
container, because the file was never inside the container at all —
just visible through it.

Volume (`-v VOLUME_NAME:CONTAINER_PATH`, e.g. `-v mydata:/app/logs`,
created with `docker volume create mydata`) — same durability, but
Docker manages and hides the actual storage path (under
`/var/lib/docker/volumes/`) instead of you specifying one. You refer
to it only by name. Both bind mounts and volumes store data on the
EC2's real disk — the difference is WHO controls the exact path, not
"container vs EC2."

Bind mounts: good for development — easy to inspect/edit directly.
Volumes: preferred in production — harder for a human to accidentally
corrupt, Docker fully owns the lifecycle. Any stateful production
service (database, persistent logs, uploads) MUST use one of these, or
every container replacement (crash, redeploy, scaling, update) wipes
its data with no warning.



## M03-P08 — Push & Pull to a Registry (Docker Hub + AWS ECR)
Docker Hub is public by default (anyone can pull `python:3.11-slim`,
no login needed). AWS ECR is private by default — real company images
often contain proprietary code/logic, so authentication is required
before push or pull.

`aws ecr get-login-password --region ap-south-1 | docker login
--username AWS --password-stdin <account>.dkr.ecr.<region>.amazonaws.com`
— generates a temporary AWS token and pipes it into `docker login`,
avoiding manual password handling.

`docker tag flask-demo:latest <ecr-uri>/flask-demo:latest` — does NOT
create a new image or duplicate data. Just adds a second name/label
pointing at the same existing image (confirmed via identical IMAGE ID).
The image must already exist locally before tagging — tag never builds
anything.

`docker push <ecr-uri>/flask-demo:latest` — reads the registry address
embedded in the tag name and uploads the real layer data there. First
push to a brand-new ECR repo uploads ALL layers (including base image
layers) since caching only skips layers the DESTINATION already has —
a fresh repo has nothing to skip. A later push with only a small code
change would skip the unchanged base layers.

Full round trip proved: build locally → tag for ECR → authenticate →
push → delete local copy → pull back down from ECR → same digest
confirms identical image, byte-for-byte. This is what allows a
completely different machine (teammate's laptop, CI runner, Kubernetes
node) to run the same image without access to the original build files.



## M03-P09 — Multi-Stage Builds (Shrinking a Bloated Image)
A container's final image carries around all build-time baggage
forever (pip itself, build tools, cached files) even though it's dead
weight after the build finishes — most of it is only needed DURING
build, not at runtime.

Multi-stage builds use 2+ `FROM` lines in one Dockerfile. Stage 1
("builder", named via `FROM ... AS builder`) does the heavy build work
(pip install, compiling). Stage 2 (final) starts fresh and only
`COPY --from=builder /path /path` the finished results — none of Stage
1's build tools or cache carry over, since Stage 1 is discarded
entirely once the build finishes.

`pip install --user` puts all installed packages in one predictable
folder (`/root/.local`) instead of scattering them across system
folders — makes `COPY --from=builder /root/.local /root/.local` clean
and complete. Also needed: `ENV PATH=/root/.local/bin:$PATH` in Stage
2, since Python/shell only search a specific PATH list, not the whole
filesystem — copying files in doesn't mean anything "knows" to look
there.

KEY INSIGHT: size reduction depends entirely on STAGE 2's base image,
since Stage 1 is discarded regardless of size. Tested live:
- Original single-stage (`python:3.11-slim`): 213MB
- Multi-stage, Stage 2 still `slim`: 194MB (~9% reduction — only saved
  a duplicate pip install, base OS bulk unchanged)
- Multi-stage, Stage 2 switched to `python:3.11-alpine`: 91.4MB (~57%
  reduction — Alpine is a genuinely minimal Linux distro)

RISK: Alpine uses `musl` libc instead of `glibc` (used by
slim/Debian-based images). Pre-compiled binary Python packages built
against glibc may fail on musl. Tested live: flask worked fine on
Alpine in this case, but this isn't guaranteed for every package —
production teams should explicitly test compatibility before
committing to Alpine, especially for packages with compiled extensions
(numpy, psycopg2, cryptography, etc.).

Resources: pythonspeed.com "Multi-stage builds #2: Python specifics",
YouTube "Docker Multistage builds explained in 8 minutes"
(https://www.youtube.com/watch?v=V0kTEk7YA70)



## M03-P10 — Docker Compose (Multi-Container App)
Real services should run in SEPARATE containers, not crammed into one
("one container, one responsibility"). This allows independent
lifecycle management — upgrading, restarting, or scaling one service
(e.g. Redis) never risks disturbing another (e.g. Flask), since
they're genuinely isolated units, not bundled together.

Docker Compose (`docker-compose.yml`) describes multiple services
together in one YAML file. `build: .` for services with our own
Dockerfile (e.g. Flask/web); `image: redis:alpine` for ready-made
public images we just pull and run as-is, no build needed.
`depends_on: [redis]` controls START ORDER only (redis starts before
web) — does NOT guarantee Redis is fully ready to accept connections,
just that its container has started.

YAML indentation is meaningful — services must be siblings under
`services:`, same indentation level, or one gets nested inside another
by mistake (caught and fixed this live).

Networking: Compose automatically creates a shared private network
with built-in internal DNS for all services in the file. Flask reaches
Redis via `host="redis"` (the service name from docker-compose.yml) —
no hardcoded IP ever needed, Docker resolves the name to the actual
(possibly-changing) internal IP automatically.

`docker compose up -d --build` — builds + starts everything, `--build`
forces a rebuild check even if an image already exists (good habit
during active development). `docker compose down` — stops AND removes
all containers plus the network Compose created, in one command.

Redis has no `-p` host port mapping — only Flask needs one, since only
Flask must be reachable from OUTSIDE the Docker network (browser/curl).
Redis is only ever accessed internally by Flask — not exposing it to
the host is also a security best practice (can't be reached externally
even by accident).

Proved live: `docker ps` after `compose up` showed TWO separate
containers (docker-lab-03-web-1, docker-lab-03-redis-1) — Compose
orchestrates real, individual containers, doesn't merge them into one.
Visit counter (`cache.incr("visits")`) incremented correctly across
requests (1, 2, 3), confirming Flask successfully read/wrote to Redis
across the container boundary.

Teach-back Q&A (P10):
Q: Why separate containers instead of one for Flask + Redis?
A: Upgrading Redis never requires touching or rebuilding Flask's
container, and vice versa — each stays independently changeable.

Q: How does Flask reach Redis without a hardcoded IP?
A: Docker Compose's automatic internal DNS resolves the service name
("redis") to its actual internal IP — no manual tracking needed.

Q: Why doesn't Redis need a -p port mapping while Flask does?
A: Redis is only ever accessed internally by Flask, never from outside
the Docker network. Flask must be reachable by an outside browser/curl,
so it needs the host port mapping; Redis deliberately doesn't, which is
also a security plus — nothing external can reach it even by accident.



## M03-P11 — Debugging Toolkit: logs, exec, inspect, stats
`docker logs <container>` — shows whatever the APPLICATION printed
(stdout/stderr) since the container started. Passive, historical
record. New requests appear as new lines appended to existing output.

`docker exec -it <container> bash` — opens an interactive shell INSIDE
an already-running container (`-i` = interactive, keep input open;
`-t` = allocate a pseudo-TTY, makes it feel like a real terminal).
Minimal base images (slim) strip out non-essential tools to stay
small — `ps` was missing entirely inside the container, a real
friction point when debugging minimal images interactively.

`docker inspect <container>` — full JSON configuration dump: IP,
volumes, env vars, restart policy, etc. — Docker's own metadata, not
app output. Use `--format '{{...}}'` (Go template syntax) to filter to
one specific field. Compose-created containers store their internal
IP nested under `.NetworkSettings.Networks.<network-name>.IPAddress`
(NOT the flat `.NetworkSettings.IPAddress`, which only applies to the
plain default bridge network). Network names with hyphens break Go
template parsing directly — need the `index` function:
`{{(index .NetworkSettings.Networks "docker-lab-03_default").IPAddress}}`

`docker stats` — the only one of the four that's LIVE and continuously
updating: real-time CPU%, memory%, network I/O, similar to `top` but
scoped to containers. The right tool specifically for "app seems slow"
complaints — logs and inspect don't reveal resource pressure at all.

Debugging trail worth remembering: wrong guess on IP path → real
parsing error → checked actual JSON structure via grep → found nested
key → hit hyphen syntax issue → used `index` workaround. This IS what
real debugging looks like — guess, fail, investigate structure, fix.

Teach-back Q&A (P11):
Q: What's the core difference between docker logs and docker exec?
A: docker logs is passive — shows what the app already printed
(stdout/stderr) since the container started. docker exec is active —
lets you actually reach in and run a command or open a shell live
inside an already-running container.

Q: Why did docker inspect --format '{{.NetworkSettings.IPAddress}}' fail?
A: That flat path only works for containers on the plain default
bridge network. Docker Compose creates its own custom-named network,
so the IP lives nested one level deeper under
.NetworkSettings.Networks.<network-name>.IPAddress instead — and the
hyphen in the network name broke direct template parsing, requiring
the index function as a workaround.

Q: Why is docker stats specifically the right tool for a "the app
seems slow" complaint?
A: It's the only one of the four that shows LIVE, continuously-updating
resource usage (CPU%, memory%, network I/O). Neither docker logs
(app output) nor docker inspect (static config) reveal resource
pressure at all — only stats measures it in real time.
