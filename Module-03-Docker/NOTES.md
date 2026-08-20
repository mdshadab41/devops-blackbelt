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
