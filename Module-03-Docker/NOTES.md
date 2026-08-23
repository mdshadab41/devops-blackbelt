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
