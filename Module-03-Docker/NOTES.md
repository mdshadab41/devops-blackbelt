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
