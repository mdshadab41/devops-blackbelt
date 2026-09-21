# Secure Checkout Gateway

A production-style networking stack built as the Module 04 (Networking)
capstone project: a load-balanced Flask API served by 3 independent
backend instances, fronted by Nginx as a reverse proxy and load
balancer, hardened with rate limiting, secured with a real CA-signed
HTTPS certificate, and made resilient to reboots via systemd.

## Architecture

                    Internet
                       |
                [ Security Group ]  <- port 80/443 allowed
                       |
                    [ ufw ]         <- port 80/443 allowed
                       |
                [ Nginx :80/:443 ]
                 |    rate limiting (10 req/s per IP, burst 20)
                 |    TLS termination (Let's Encrypt)
                 |    HTTP -> HTTPS redirect
                       |
              [ least_conn load balancing ]
                 /       |        \
        backend-1   backend-2   backend-3
        (Gunicorn)  (Gunicorn)  (Gunicorn)
        :5001       :5002       :5003
        2 workers   2 workers   2 workers
             \          |          /
              [ systemd services ]
              (auto-restart, survives reboot)


## Components

- **Flask app** (`app.py`): a minimal API with `/` (identifies which
  backend instance served the request) and `/health` (unmonitored,
  unthrottled health check endpoint).
- **Gunicorn**: production WSGI server, 2 worker processes per
  instance, replacing Flask's single-threaded development server.
- **systemd**: each backend runs as a real system service
  (`checkout-backend-1/2/3.service`), with `Restart=always` and a
  restart-rate limit (`StartLimitBurst=5` / `StartLimitIntervalSec=60`)
  to recover automatically from crashes or reboots without silently
  masking a persistently broken app.
- **Nginx**: reverse proxy, load balancer (`least_conn`), rate limiter,
  and TLS termination point.
- **Let's Encrypt (Certbot)**: real, CA-signed HTTPS certificate — no
  browser warnings, verified via `curl` succeeding without `-k`.

## Design Decisions

- **`least_conn` over round-robin**: chosen since request processing
  time isn't guaranteed uniform; routes new requests to whichever
  backend is currently least busy rather than blindly cycling.
- **Rate limiting scoped to `/` only, not `/health`**: monitoring and
  health checks should never be throttled by the same rule protecting
  against abuse on real traffic.
- **`nodelay` on the rate limit burst**: burst-covered requests are
  served immediately rather than artificially delayed, since the goal
  is absorbing legitimate traffic spikes, not deliberately slowing
  clients down.
- **systemd over nohup/`--daemon`**: both of the latter only survive a
  disconnected terminal session, not a full machine reboot. Proven
  directly — see Known Incidents below — that only a real systemd
  service reliably survives an actual reboot with zero manual
  intervention.
- **Environment variables over `sys.argv` for configuration**: avoids
  an entire class of bugs where a process manager's own command-line
  flags get mistaken for application arguments (see Known Incidents).

## Security Hardening Applied

- Security Group: only ports 22 (SSH), 80 (HTTP), 443 (HTTPS) allowed,
  source `0.0.0.0/0`.
- `ufw`: same three ports explicitly allowed at the OS level,
  independent of the Security Group (defense in depth).
- Rate limiting: 10 requests/second per IP, burst of 20, on all
  customer-facing routes.
- Real CA-signed TLS certificate (Let's Encrypt), not self-signed —
  provides genuine identity verification, not just encryption.
- HTTP automatically redirects to HTTPS (added by Certbot).
- Backend Flask/Gunicorn instances bound to `127.0.0.1` only — never
  directly reachable from outside, only through Nginx.

## Known Limitations / Honest Gaps

- **Domain uses `nip.io`, not a real registered domain.** This is a
  free testing workaround (encodes the server's IP directly in the
  domain name) — genuinely proven, mid-project, to break permanently
  the moment the server's IP changes (a real EC2 reboot changed the IP
  during this build, requiring a manual domain and certificate update).
  A real production deployment requires either a real, owned domain
  name or an AWS Elastic IP to avoid this entirely.
- **No database tier.** This project only demonstrates the web/app
  tier's networking; a real checkout system would also need a
  properly isolated data tier (see the Module 04 Architecture notes,
  P19, for the intended design).
- **`nip.io`'s IP-encoding also means TLS certificates tied to it are
  inherently short-lived in practice** — any future reboot changing
  the IP will require re-issuing the certificate again for the new
  domain.

## Real Incidents Solved During This Build

1. **Recurring reboot-killed backends** (a problem that disrupted
   nearly every earlier problem in this module): root-caused to
   `nohup`/`--daemon` only surviving a disconnected terminal, never a
   full reboot. Fixed permanently with proper systemd service files —
   verified with a real, unplanned mid-project reboot that the
   backends came back online automatically, with zero manual steps.
2. **Certbot's Nginx plugin failing to auto-install a certificate**:
   root-caused to `server_name _;` (a generic wildcard) not literally
   matching the target domain, which Certbot's automation requires.
   Fixed by setting `server_name` to the exact domain before retrying.
3. **A mid-project EC2 reboot changing the public IP**, permanently
   breaking the `nip.io` domain in use (proven live: the old domain
   still resolves to the old, now-wrong IP, since there's no real DNS
   record to update). Fixed by generating a new `nip.io` domain
   matching the current IP and re-issuing the certificate for it.
4. **`curl http://127.0.0.1/` returning 404 after `server_name` became
   domain-specific**: root-caused to Nginx now strictly matching on
   the `Host` header, which plain loopback curl doesn't set to match —
   not an actual config bug, just a testing-method mismatch, confirmed
   by explicitly setting the correct `Host` header.

## Verification Evidence

- Load balancing: confirmed `least_conn` routes fewer requests to an
  artificially slow backend under concurrent load (see NOTES.md, P09).
- Rate limiting: 30 near-simultaneous requests produced 23 successful
  (200) and 7 rate-limited (503) responses, matching the configured
  `rate=10r/s, burst=20` behavior.
- HTTPS: `curl -v` from an external laptop succeeded with a clean
  `200 OK` and **no `-k` flag required** — definitive proof of genuine
  CA-trusted HTTPS, not self-signed.
- Reboot resilience: `sudo reboot` (both a deliberate test and a real,
  unplanned later reboot) followed by `ss -tuln` and `curl` confirmed
  all 3 backend services were already running automatically upon
  reconnection, with zero manual intervention required.

## Files

- `app.py` — the Flask application
- `/etc/systemd/system/checkout-backend-{1,2,3}.service` — systemd
  service definitions (not tracked in this repo; documented here for
  reference)
- `/etc/nginx/sites-available/secure-checkout-gateway` — Nginx
  reverse proxy, load balancer, rate limiter, and TLS config (not
  tracked in this repo; documented in NOTES.md)
