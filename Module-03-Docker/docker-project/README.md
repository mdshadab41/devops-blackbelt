# Visit Tracker — Flask + Redis (Dockerized Mini Project)

A small, production-hardened service that counts visits using Flask and Redis, built as the Module 03 (Docker) capstone project. This project demonstrates the full lifecycle of a container: build, harden, test, scan, and ship securely.

## Architecture

Two services, orchestrated with Docker Compose:

- web — Flask API (multi-stage build, Alpine final image)
- redis — official redis:alpine image, used as a visit counter store

Routes:
- GET / — increments and returns the visit count
- GET /health — checks Redis connectivity, returns 200 (healthy) or 503 (unhealthy) — deliberately separate from / so health checks never pollute the actual visit count

## Key Design Decisions

Multi-stage build + Alpine final image: Stage 1 (python:3.11-slim) installs dependencies where pip/build tools work reliably. Stage 2 (python:3.11-alpine) only copies the finished result. Result: 116MB final image, and zero CRITICAL CVEs (Trivy), since Alpine's minimal package set never included the vulnerable packages found in the slim-based equivalent.

Non-root user: Runs as appuser, not root — limits the blast radius if the app is ever compromised. Verified live via docker exec whoami.

Dedicated /health route: Deliberately separate from / to avoid the health check silently incrementing the visit counter every 30 seconds.

Environment-based configuration: Redis host/port are read via os.environ.get(default), not hardcoded.

Dependency pinning: flask==3.1.3, redis==8.1.0 — exact versions to avoid dependency-hell version conflicts.

Redis readiness via Compose healthcheck: web waits for Redis's own healthcheck (redis-cli ping) to genuinely pass — condition: service_healthy — rather than just waiting for the container to start.

Resource limits: web is capped at 256MB RAM / 0.5 CPU (mem_limit, cpus in Compose). Note: redis was NOT given a limit in this iteration — a known gap, listed below.

## Security Scanning Results

- Trivy (trivy image --severity CRITICAL): 0 CRITICAL vulnerabilities across the OS and all Python packages.
- Dockle: All controllable findings resolved (non-root user, no :latest tag, clean apk cache). One FATAL finding remains, originating from the official python:3.11-alpine base image's own internal Python-compilation build steps — outside this project's control, documented rather than ignored.
- Cosign: Image signed by DIGEST (not tag) with a private key; verified successfully with the matching public key. Verification against a wrong/unrelated key was tested and correctly failed.

## End-to-End Verification (Proof, Not Just Claims)

Success path: curl / three times returned visits: 1, 2, 3, confirmed sequential and correct.

Failure/recovery path: Stopped the redis container, /health correctly returned 503 unhealthy/unreachable. Docker's own HEALTHCHECK also marked web as unhealthy, independently confirming the same problem. Restarted redis, both containers automatically returned to healthy with zero manual intervention.

Resource limits: Verified live via docker stats — 34.43MiB / 256MiB, confirming the configured limit is genuinely enforced.

## Deployment

Image pushed to AWS ECR: 806528484602.dkr.ecr.ap-south-1.amazonaws.com/visit-tracker:1.0.0, signed by digest (sha256:87a9e758...), not tag, per Cosign best practice.

## AWS Resource / Lifecycle Note

- ECR repository visit-tracker remains active in ap-south-1, containing the signed 1.0.0 image. Negligible storage cost, well within Free Tier limits.
- EC2 EBS volume was permanently resized from 8GB to 20GB during this project (see NOTES.md for the full procedure) — a genuine production fix for repeated disk-full incidents, still within AWS Free Tier's 30GB allowance, at no ongoing cost.

## Known Gaps / Lessons Learned

- redis service has no resource limit — only web was hardened in this iteration.
- Real bug solved during development: switching to a non-root user after copying pip packages into /root/.local (root's own home directory) created a silent permission conflict — appuser could never read files sitting in root's territory, even though PYTHONPATH correctly pointed at them. Fixed by redirecting the install location to /home/appuser/.local via PYTHONUSERBASE. Full debugging trail documented in NOTES.md.
- Disk-full incident, twice: hit "no space left on device" during Trivy's database download, even after manual cleanup. Root-caused to the EC2 instance's disk being genuinely undersized (8GB) — fixed permanently via an EBS volume resize rather than repeated reactive cleanup.
- Health check failure detection took longer than the configured 2-second Redis timeout suggested — worth investigating further in a real production setting.

## Tech Stack

Flask 3.1.3, Redis 8.1.0 (redis-py client), Docker multi-stage builds, python:3.11-slim (build) to python:3.11-alpine (runtime), Docker Compose, Trivy, Dockle, Cosign, AWS ECR.
