# Module 03 — Docker Revision Sheet

## 1. Core Fundamentals & Dockerfile Syntax

**Image vs Container**: Image = read-only blueprint (like a class/.exe file).
Container = running instance of an image (like an object/running process).
One image → many containers.

**P02 Basics**: `docker ps` = running containers only. `docker ps -a` = all,
including stopped. `docker container prune` = remove all stopped containers
at once. Exit code 0 = success, non-zero = error (same Unix convention as
bash $?). Docker = client (messenger) + daemon (dockerd, does the real
work) — verify with `systemctl status docker`.

**Namespaces vs Cgroups** (P01): Namespaces = the walls — control what a
process can SEE (PID, network, filesystem). Cgroups = the meter — control
what a process can USE (CPU, RAM, disk). Containers share the host kernel
(no OS boot) → start in milliseconds vs a VM's 30-60s boot.

**P04 Filesystem Isolation**: An image's filesystem is completely separate
from the host. WORKDIR /app creates a folder INSIDE the image, not on the
host. Nothing from the host exists inside a container unless explicitly
COPYed in or mounted — real isolation/security property (e.g. host AWS
credentials in ~/.aws/ are NOT automatically visible inside a container).

**Layers & Caching** (P03, P05): Each Dockerfile instruction = one stacked
layer (a diff from the layer below). Docker caches layers top-to-bottom —
put rarely-changing steps (deps) BEFORE frequently-changing steps (app
code) so only the changed layer + everything after it rebuilds. Proved
live: full build 10.6s → rebuild with no changes 0.0s (all cached) →
rebuild after only code change ~0.1s (only that layer + below rebuilt).

**Dockerfile Instruction Reference**:

| Instruction | Runs When | Purpose |
|---|---|---|
| FROM | Build | Sets base image (layer 1) |
| WORKDIR | Build | Sets/creates current directory inside image |
| COPY | Build | Copies files from build context into image (dest needs trailing path, e.g. .) |
| ADD | Build | Like COPY + auto-extracts archives + URL fetch — prefer COPY unless you need the extra magic (implicit behavior risk) |
| RUN | Build | Executes a command, bakes result into a layer (e.g. pip install, apt-get) |
| CMD | Container start | DEFAULT command/args — fully REPLACED if docker run passes extra args |
| ENTRYPOINT | Container start | FIXED command — docker run args get APPENDED, not replaced. Combine: ENTRYPOINT ["python3"] + CMD ["app.py"] |
| USER | Build (switches identity from here on) | Switches to a non-root user — MUST come after useradd+chown, and creating a user ≠ switching to it (real bug hit in P18) |
| EXPOSE | N/A | Pure documentation/metadata — does NOT open a port by itself |
| HEALTHCHECK | Runs periodically once container is up | Functional check (e.g. curl -f) — "Up" alone only means process hasn't crashed, NOT that it's working |
| ENV | Build | NEVER put secrets here — baked permanently into image layer, extractable via docker inspect/docker history by anyone who can pull the image |

**Build context**: the . in `docker build -t name .` — tells Docker "look
here for the Dockerfile and anything COPY needs."

## 2. Networking

**Bridge network isolation** (P06): containers get their own private
network namespace/internal IP — analogy: EC2 = apartment building (own
front door/localhost), container = an apartment inside (own separate
door). curl localhost:PORT from the EC2 itself fails even if the app is
running fine inside the container — nothing is listening at the EC2's
own address.

**Port mapping**: `-p HOST_PORT:CONTAINER_PORT` — acts like a doorman,
forwards host-port traffic into the container port. Order matters: LEFT
= host (what you type), RIGHT = container (what the app expects).

**3-layer reachability chain** — ALL THREE must align or you get
"connection refused" with the same symptom but different root cause:
1. App binds to 0.0.0.0 (all interfaces), not 127.0.0.1 (localhost-only)
2. Docker -p port mapping exists
3. AWS Security Group allows inbound traffic on that host port

**Compose networking** (P10): Compose auto-creates a shared private
network + internal DNS for all services in one docker-compose.yml —
service name (e.g. redis) becomes a resolvable hostname automatically, no
hardcoded IPs ever needed. depends_on only controls START ORDER, does NOT
guarantee the dependency is actually ready to accept connections.

## 3. Data Persistence

**Container filesystem is temporary** (P07): delete the container →
anything written inside it is gone permanently. Proved live: log file
vanished ("No such file or directory") after docker rm + new container
from same image.

**Bind mount**: `-v HOST_PATH:CONTAINER_PATH` (e.g. -v ~/logs:/app/logs) —
YOU specify and know the real path, browsable directly from the host.
Good for development.

**Volume**: `-v VOLUME_NAME:CONTAINER_PATH` (e.g. -v mydata:/app/logs,
created via docker volume create) — DOCKER manages/hides the actual path
(/var/lib/docker/volumes/...). You only reference it by name. Good for
production — harder for a human to accidentally corrupt.

Both ultimately store data on the host's real disk — the difference is
WHO controls the exact path, not "container vs host."

## 4. Registries & Supply Chain

**Push/Pull mechanics** (P08): docker tag does NOT create new content —
just adds a second name/label pointing at the SAME existing image
(confirmed via identical IMAGE IDs). ECR is private by default — needs
auth: `aws ecr get-login-password --region <region> | docker login
--username AWS --password-stdin <account>.dkr.ecr.<region>.amazonaws.com`.
ECR tokens expire after 12 HOURS — real production pattern is baking
fresh auth into every CI/CD run, never relying on a long-lived login.

**First push to a brand-new repo uploads ALL layers** (including base
image layers) — caching only skips layers the DESTINATION already has; a
fresh repo has nothing to skip.

**ImagePullBackOff — two distinct causes** (P15), distinguishable by
error message:
1. Wrong/nonexistent image name: "pull access denied... repository does
   not exist or may require 'docker login'" — deliberately AMBIGUOUS
   (could be typo OR private repo you're not authenticated to)
2. Expired/missing auth on a KNOWN repo: "authorization failed: no basic
   auth credentials" — more specific, clearly an auth problem. Fix:
   re-run the ECR login command.

**Tag vs Digest** (P18, P19): :latest (or any tag) is a MOVEABLE pointer
— can be reassigned to different content at any time. A DIGEST
(sha256:...) is a cryptographic hash of the exact content — can never
point to different content. Get it via:
`docker inspect --format='{{index .RepoDigests 0}}' <image>`

**Cosign signing** (P19): Docker has ZERO built-in authenticity check —
docker pull trusts whatever bytes are at a registry address. Cosign
closes this with public/private key pairs (like SSH): sign with PRIVATE
key (secret, password-protected), verify with PUBLIC key (shareable, no
password needed). ALWAYS sign by DIGEST, not tag. Proved live: verifying
with a wrong/unrelated public key fails clearly ("no matching
attestations") — confirms only the true matching key pair can produce a
valid verification.

## 5. Multi-Container Apps (Compose)

build: . for your own Dockerfile-based services; image: name:tag for
ready-made public images (no build needed). Services are SIBLINGS under
services: — same YAML indentation, or one gets nested inside another by
mistake (real bug hit in P10).

`docker compose up -d --build` — build + start everything, --build forces
a rebuild check even if an image exists. `docker compose down` — stops
AND removes all containers + the network Compose created, in one command.

Internal-only services (e.g. Redis) should NOT get a -p host port mapping
— only services reached from OUTSIDE the Docker network need one. Not
exposing internal services is also a security best practice.

## 6. Debugging Toolkit

| Tool | Shows | Notes |
|---|---|---|
| docker logs <c> | What the APP printed (stdout/stderr) | Passive, historical |
| docker exec -it <c> bash | Live shell INSIDE a running container | -i=interactive, -t=pseudo-TTY. Minimal images (slim) often lack basic tools (ps was missing) |
| docker inspect <c> | Full JSON config (IP, volumes, env vars) | Docker's own metadata, not app output |
| docker stats | LIVE, continuously-updating CPU/mem/network | Only tool that shows resource pressure — right tool for "app seems slow" |

**P11 hyphen workaround**: Go template syntax (--format) breaks on
hyphens in key names. Compose network names contain hyphens (e.g.
docker-lab-03_default) — use the index function:
`{{(index .NetworkSettings.Networks "network-name").IPAddress}}`
(Compose containers store IP nested under Networks.<name>, not the flat
.NetworkSettings.IPAddress path, which only works for the default bridge
network.)

**P16 Disk-Full diagnostic sequence**: `df -h` (OS-level %) → `docker
system df` (Docker-level breakdown by category + reclaimable amounts) →
review `docker images` deliberately, decide keep/remove → `docker rmi`
specific images → `docker builder prune -a` for build cache. Real
numbers from live incident: 77%→65% disk usage, 814.8MB build cache
reclaimed. Docker never auto-cleans anything — accumulates silently
across every build. `docker system prune` (no flags) only removes
DANGLING (untagged) images by default, needs -a for all unused images —
don't blindly nuke everything without reviewing first.

## 7. Security Scanning & Hardening

**Trivy** (P17): scans actual installed PACKAGES/OS inside the built
image against public CVE databases — does NOT care about Dockerfile
syntax. 229 total findings on a slim-based image is NORMAL — triage by
severity, don't try to fix everything. "Fixed Version" column empty means
no patch exists yet. Don't force-remove "essential" packages (apt blocks
this) — trading a known low-risk CVE for an unknown, unpredictable
breakage is the wrong trade. Real fix was switching to Alpine base —
eliminated CVEs AND reduced size simultaneously.

**Dockle** (P18): checks image CONSTRUCTION habits, not CVEs. Severity
labels (FATAL/WARN/INFO) reflect "how avoidable/unambiguous," not "how
dangerous" — FATAL apt-cache leftover is pure waste with zero downside to
fixing; WARN root-user has legitimate exceptions sometimes. Key fixes:
non-root USER, clean apt cache in the same RUN line (&& rm -rf
/var/lib/apt/lists/*), avoid :latest tag.

**Resource limits & HEALTHCHECK** (P22): `--memory=256m --cpus=0.5` — no
limit = cgroups don't restrict at all, a leak can starve the whole host
("noisy neighbor"). `HEALTHCHECK CMD curl -f ...` — MUST use -f flag,
plain curl returns exit 0 even on a 500 error (successfully got A
response, just an error one) — HEALTHCHECK relies entirely on exit code.

## 8. Container Runtime Architecture

**Full chain under the hood** (P23): docker (CLI client, just a
messenger) → dockerd (daemon, handles image pulls/-p/-v/networking, does
NOT touch the kernel itself) → containerd (manages image storage + full
container lifecycle, also does NOT touch the kernel directly) → runc
(low-level, one-shot tool that actually calls into the Linux kernel to
create namespaces/cgroups and start the process, then exits).

**Podman**: daemonless — CLI directly manages containers, no
always-running background process at all. Rootless-first design (Docker
added rootless mode later). Security benefit: no root-owned daemon to
escalate through if compromised.

**Real-world fact**: modern Kubernetes clusters run containerd DIRECTLY
as their runtime, without Docker in the middle — Kubernetes deprecated
direct Docker support in favor of CRI-compliant runtimes. Directly
relevant for Module 06/15 (Kubernetes/EKS).

## 9. Manager Communication Patterns

Lead with IMPACT/numbers first, technical "how" second. Be honest about
testing SCOPE (e.g. "tested locally" vs "verified in production") rather
than overstating unmeasured claims. Always name the SPECIFIC lever that
moved the needle most (e.g. "base image choice drove 103MB of the 122MB
total drop, not the multi-stage pattern alone"). Flag trade-offs
explicitly rather than hiding them (e.g. Alpine's glibc/musl risk) —
builds trust.

## 10. Interview Traps & Recurring Themes

**"Build success ≠ runtime success"** — hit in P12 (WORKDIR after COPY:
build succeeded, runtime failed) and P14 (dependency conflict: pip
install succeeded, import failed at runtime). ALWAYS test with docker
run, not just docker build.

**"Up ≠ working"** — hit in P13 (crash loop), P24 (OOM red herring —
container looked fine, was actually silently failing under concurrency),
P25 Scenario 3 (worker Up 3 days, not processing jobs, no HEALTHCHECK to
catch it). "Up" only means the process hasn't crashed.

**Tag vs Digest** — appears in BOTH Dockle (avoid :latest, P18) and
Cosign (sign by digest not tag, P19) — same underlying problem
(mutability) surfacing in two unrelated tools.

**A restart policy is not a fix** — P13: on-failure/always just retry
forever without resolving the underlying cause; only useful for
recovering from TRANSIENT issues.

**Question the "obvious" hypothesis** — P24's biggest lesson: the
scenario's own setup (--memory=100m) strongly implied OOM, but docker
inspect's OOMKilled:false proved it wrong. Real root cause was Flask's
single-threaded dev server under concurrent load. Verify with direct
evidence, don't just accept what the setup implies.

**Minimal base images = simultaneous wins** — Alpine switch in P09
reduced size (213MB→91.4MB) AND eliminated CVEs (P17, 3 CRITICAL→0) —
one architectural decision solving two different problems.
