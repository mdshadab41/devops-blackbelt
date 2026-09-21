## M04-P01 — How Networking Actually Works (IP, Ports, Sockets)

### The Core Idea
Every network request is really just answering: "how does a request find 
point B from point A, and what identifies this specific conversation?"

Analogy: making a phone call.
- IP address = phone number (which machine)
- Port = extension number (which app on that machine)
- Socket = the actual live phone call — a specific pairing of 
  (my number, my ticket) + (their number, their extension)

### Client vs Server Ports — Different Behavior
- **Server port**: fixed and known (e.g. Flask on port 5000). Has to stay 
  the same so people can always find it — like a business phone number.
- **Client (caller) port**: ephemeral — a new random port (e.g. 54321) is 
  assigned for every new connection, even to the same destination.

Why ephemeral ports exist: if I open 3 browser tabs to the same website,
each is a separate conversation. My IP stays the same for all 3, but each
gets a different ephemeral port so my OS can tell the 3 conversations 
apart. The IP alone isn't enough to separate them — I'm the same caller 
each time.

**Correction I made during this session:** my IP address does NOT change 
per-request. Only my PORT is ephemeral. IP = fixed (per session). 
Port = new, every new connection.

### The Full Identifier of Any Connection
(caller IP, caller port) + (server IP, server port)

This 4-part combination is what makes every single connection unique, 
even when the server is handling thousands of people at the same fixed 
port simultaneously.

### Loopback vs Real Network — 127.0.0.1 vs 0.0.0.0
- `curl http://localhost:5000` from ON the same server → uses the 
  **loopback interface** (127.0.0.1). Traffic never touches the real 
  network card — it's a shortcut, like talking to yourself internally.
- `app.run(host="127.0.0.1")` → app ONLY accepts loopback traffic. 
  Anyone outside the server gets rejected immediately.
- `app.run(host="0.0.0.0")` → app listens on ALL interfaces, including 
  the real network card. This is required for anyone outside the 
  machine to reach it.

**Real-world relevance:** "works when I curl localhost on the server, 
but nobody outside can reach it" is one of the most common real 
misconfigurations — almost always a 127.0.0.1 vs 0.0.0.0 binding issue.

### Refused vs Timeout — The Most Important Diagnostic Signal
| Symptom | Meaning | Speed |
|---|---|---|
| Connection refused | Request REACHED the machine, but was actively rejected (app not listening, or wrong binding) | Fast (instant) |
| Connection timed out / hangs | Request was silently dropped somewhere BEFORE reaching the app (usually Security Group or firewall) | Slow (10-30+ sec) |

**Why timeout is slow, specifically:** the blocking device (e.g. AWS 
Security Group) doesn't "wait" — it drops the packet instantly with zero 
response. It's MY OWN machine that waits, because it sent a request and 
has no way to know whether the silence means "still in transit" or 
"never arriving." Since both look identical (silence), my machine has no 
choice but to wait out its own timeout setting before giving up.

Analogy: mailing a letter to someone who never replies. You don't 
instantly know they never got it — you keep expecting a reply for a 
while, then eventually conclude something's wrong. Same mechanism, 
just computers instead of mail.

### Why This Matters Going Forward
- This refused-vs-timeout signal is the FIRST diagnostic check in 
  M04-P12 (Security Group incident) and M04-P13 (SSH incident) later 
  in this module.
- Same fixed-server-port pattern reappears in Module 06 (Kubernetes) — 
  a Service always exposes one stable port even though the actual pods 
  behind it keep changing. Same idea, different layer.

### Key Takeaway
Fixed IP + fixed port (server) vs fixed IP + ephemeral port (client).
Refused = rejected at the app. Timeout = silently dropped before 
reaching the app.
## M04-P02 — DNS Resolution Walkthrough

### The Full DNS Chain
Domain name to IP address doesn't happen in one step. Full chain:

1. Local cache check (OS and /etc/hosts) - fastest, checked first
2. Local stub resolver (127.0.0.53 on Ubuntu, via systemd-resolved) -
   a middleman running ON your own machine, NOT the real DNS server
3. Upstream DNS resolver (ISP's, or a public one like 8.8.8.8)
4. If not cached upstream either: root servers to TLD servers (.com) to
   authoritative servers (GitHub's own) - full lookup chain
5. IP returned, cached locally, THEN the real HTTP request is sent

Correction made during this session: 127.0.0.53 is NOT the ISP's
DNS server - the 127.x.x.x range always means "myself" (loopback),
same rule learned in P01. It is a LOCAL stub resolver running on the
EC2 instance itself, which then forwards out to the real upstream
resolver.

### Why Local Caching Exists
Every DNS lookup is a full network round-trip (send question, wait for
reply) - same request/wait pattern from P01. Caching avoids repeating
that delay for information that rarely changes.

### Reading dig Output
Command used: dig github.com

Key fields:
- SERVER: 127.0.0.53#53 -> the local stub resolver, not the real DNS
  server
- ANSWER SECTION -> the actual IP returned
- The number before "IN A" (e.g. 11) -> TTL (Time To Live) - how
  many seconds this answer is still valid to keep cached

### TTL - Why It Matters (Short vs Long)
- Short TTL (e.g. 11 sec, common for GitHub-scale services) ->
  changes propagate to everyone almost instantly, but more frequent
  DNS lookups (slightly more load, less caching benefit)
- Long TTL (e.g. 24-48 hrs) -> better caching/performance, but SLOW
  to propagate any change

### Real Incident Pattern: Stale Cache During Migration
Scenario: company migrates to a new server, updates DNS correctly, but
TTL was set to 1 hour. A customer still sees the OLD site 10 minutes
after migration.

This is NOT a bug. The DNS record is correct - the customer's
resolver simply cached the OLD answer before the migration and hasn't
expired it yet.

Key lesson: TTL cannot be fixed reactively. Once a resolver caches
an answer with "valid for 1 hour," the company has NO way to reach into
that resolver and force it to expire early. The only real fixes are:
- The customer manually flushes their own local DNS cache (their
  action, not the company's)
- Wait out the remaining TTL window naturally

The real takeaway: if fast failover matters (planned migrations,
load balancers, CDNs), TTL must be lowered in advance, before the
incident - not adjusted during one. This is a proactive decision, not
a reactive fix.

### Why This Matters Going Forward
This exact stale-cache-during-migration pattern is the core of
M04-P14 (DNS incident) later in this module - distinguishing "DNS is
actually broken" from "DNS is correct, but caches haven't caught up yet."

### Key Takeaway
DNS lookups involve multiple hops (local cache to stub resolver to
upstream to authoritative), and TTL controls how long a wrong/stale
answer can survive after being fixed. TTL decisions must be made
BEFORE an incident, not during one.

## M04-P03 - TCP vs UDP

### The Core Difference
TCP = "phone call" - guarantees everything arrives, correctly, in order.
UDP = "fire and move on" - no guarantees, no re-sending lost data.

### TCP's Defining Behaviors
1. Handshake first (3-way handshake: SYN, SYN-ACK, ACK) before any real
   data moves - both sides confirm "ready?" first
2. Guaranteed delivery - if data is lost, TCP notices and re-sends it
3. Guaranteed order - pieces are reassembled in correct order even if
   they arrive out of order over the network

### UDP's Defining Behavior
No handshake, no delivery guarantee, no re-sending. Fires data and
moves on. If something is lost, it is simply gone - nobody notices
or fixes it.

### Speed Tradeoff (correction made during this session)
UDP is faster than TCP, not the other way around. TCP's handshake and
constant "did you get that?" confirmation checks all take extra time
(each check is a round trip). UDP skips all of that, so there is less
total work before data arrives - hence faster, but with zero guarantees.

### Who Uses What
- TCP: HTTP/web traffic (Flask, curl, browsers), file transfers -
  correctness matters more than raw speed
- UDP: live video calls, gaming, DNS lookups - speed matters more than
  guaranteed delivery of every single piece

### Diagnostic Framework: "What does each side actually DO?"
1. Identify the two things being compared
2. State each one's ONE defining behavior, in one sentence
3. Apply that behavior directly to the scenario - what would you
   EXPECT to happen, given that behavior?
4. If your expectation matches the scenario, that is likely the
   correct root cause - state it using the actual behavior as the
   reason, not just "because that is how it works"

### Applied Example: Video Call Freezing, Website Fine
Rough network conditions cause packet loss on both TCP and UDP traffic.
- TCP (website): lost packet is automatically re-sent - page loads
  slightly slower but arrives complete. Problem is hidden from the user.
- UDP (video call): lost packet (one video frame) is never re-sent -
  it is just gone. This shows up as a visible freeze/glitch on screen.

This is not a bug - it is UDP's design tradeoff working exactly as
intended (speed over reliability).

### Key Takeaway
TCP hides network problems from the user by fixing them automatically,
at the cost of speed. UDP is fast because it does not bother fixing
anything, which is why the SAME network issue produces very different
visible symptoms depending on which protocol is carrying the traffic.

### Real-World Application: How Zoom Uses BOTH TCP and UDP
Most real applications don't use purely one protocol - they split
traffic based on what each specific TYPE of data actually needs.

Zoom example:
- Joining a meeting (authentication, meeting ID verification) -> TCP.
  Must complete reliably, no partial/lost steps allowed - matches
  TCP's connection-oriented, guaranteed-delivery design.
- Live video/audio stream -> UDP. A dropped frame/glitch is far less
  disruptive than pausing the whole stream to wait for a perfect
  re-send. Same reasoning as the video-freezing example above.
- Text chat during the call -> TCP. A silently dropped chat message
  would just vanish with no warning (unacceptable) - every character
  must arrive, correctly, in order.

Interview-level insight: when asked "does a video calling app use TCP
or UDP," the strong answer is "it depends on the type of traffic
within the app" - not picking just one. Real systems intelligently
split traffic by protocol based on whether reliability or speed
matters more for that specific piece of data.

### TCP's 3-Way Handshake (added detail)
1. SYN - client: "I want to connect, are you there?"
2. SYN-ACK - server: "Yes, heard you (ACK), and confirming my side
   works too (SYN)"
3. ACK - client: "Confirmed, line works both ways, let's begin"

Only after all 3 steps complete does real data ever move. This is
exactly why TCP is slower than UDP - 3 full round trips happen BEFORE
a single byte of actual data (e.g. a curl request) is sent.

UDP does ZERO handshake steps - it is "connectionless." The sender
fires real data immediately with no upfront check that the destination
is even listening. TCP is "connection-oriented" - the handshake
literally establishes a tracked conversation before data flows.

## M04-P04 - curl Deep-Dive

### Why curl Hides Details by Default
Same reasoning as DNS caching (P02) - most of the time you just want
the actual content (webpage/JSON), not the plumbing underneath. But
when something breaks, the plumbing (connection status, headers,
timing) becomes the important part, not the content. curl hides
detail by default for clean everyday use, but reveals it on request
via the -v (verbose) flag - exactly when debugging needs it most.

### Reading `curl -v` Output
Command used: curl -v http://localhost

Real output showed:
- "Host localhost:80 was resolved" - DNS resolution step happens even
  for localhost (same chain as P02)
- IPv6 (::1) and IPv4 (127.0.0.1) - both are loopback ("myself"),
  just two different address formats for the same concept from P01
- "connect ... failed: Connection refused" - fast, active rejection,
  not a timeout

### Refused vs Timeout - Generalized Rule (correction made this session)
Refused = OS-level, INSTANT rejection meaning "nothing is listening on
this port on this machine." This applies regardless of WHICH port
number is being tested, and applies even for localhost traffic where
NO Security Group is ever involved (localhost never crosses a real
network boundary).

Timeout = a SILENT drop that happens BEFORE the request ever reaches
the destination machine's OS at all. This always implies a real
network hop was involved (Security Group, firewall, routing issue) -
timeout can never happen for pure localhost traffic, because there is
no network boundary to be blocked at.

### Why curl -v on localhost:80 Showed "Refused"
Nginx is not installed yet, so nothing is listening on port 80. When
the request arrives, the OS (kernel) itself - not any app - instantly
detects "no application here" and sends back the refusal. This happens
at the OS level with zero app involvement, and confirmed to behave
identically when tested against port 5000 (no Flask app running there
either) - same refused result, same reasoning, proving the behavior is
about "is anything listening" and not about which specific port number
is used.

### Why This Matters Going Forward
This refused-vs-timeout distinction, now fully generalized, is the
FIRST diagnostic check for every incident from M04-P11 onward. Refused
points to an app/OS-level problem on the target machine. Timeout points
to a network-layer block (Security Group, firewall) before the machine
was ever reached.

### Key Takeaway
curl -v reveals the full connection plumbing (DNS resolution, IP
attempts, connect result) hidden by default. "Refused" always means
OS-confirmed "nothing is listening" regardless of port or whether it
is localhost. "Timeout" always implies a real network-layer block
occurred before the destination machine's OS was ever reached.

## M04-P05 - Network Diagnostics Toolkit (ss, netstat, tcpdump, traceroute, nc)

### ss - Socket Statistics (modern replacement for netstat)
Command used: ss -tuln
Flags: -t (TCP), -u (UDP), -l (listening only), -n (port numbers, no
DNS lookup - same lookup cost concept from P02)

Real output showed SSH (0.0.0.0:22 - all interfaces, reachable from
outside per P01's binding rule) and another service on 127.0.0.1:6010
(loopback only - unreachable from outside regardless of Security Group).

### Refined 3-Layer Failure Model
Testing curl to 127.0.0.1:6010 from an external laptop revealed the
full, corrected layered order for ANY connection attempt:
1. Security Group (outermost gate, checked FIRST) - blocked here =
   TIMEOUT (silent drop, request never proceeds further)
2. Network interface / binding (0.0.0.0 vs 127.0.0.1) - reaches the
   machine but wrong interface = REFUSED (OS-level, instant)
3. The application itself (crashed / not running) - nothing listening
   on the correct interface+port = also REFUSED

Key correction: "refused" can ONLY happen if the request successfully
passes the Security Group first. Diagnosis should always proceed
outside-in: Security Group -> binding/interface -> application.

### nc (netcat) - Fast Port Reachability Test
Commands used and real results:
- nc -zv localhost 22 -> "succeeded" (matches ss -tuln showing SSH
  listening)
- nc -zv localhost 9999 -> "Connection refused" (matches P04's OS-level
  instant rejection model - nothing listening, no Security Group
  involved for localhost)

nc is faster than curl for pure reachability checks since it does not
attempt a full HTTP request - just tests if the TCP port accepts a
connection.

### traceroute - Mapping the Network Path Hop by Hop
Command used: traceroute google.com

Confirmed real traffic passes through MANY intermediate hops (not a
direct connection) before reaching the destination (final hop reached
Google's own domain, 1e100.net).

Real incident along the way: traceroute was not installed, and
installing it failed due to an UNRELATED broken kernel headers
dependency (linux-headers-aws expected version 1011, but 1011 was not
actually installed - leftover from an earlier incomplete kernel
update, unrelated to networking). Root-caused via `apt list --installed
| grep linux-headers` + `uname -r` comparison, fixed properly via
`apt --fix-broken install` (installs the missing headers package,
does NOT touch the running kernel or require a reboot) rather than
blindly following the suggested command without understanding it first.

Key finding: some hops showed `* * *` (no reply). CORRECTED
ASSUMPTION: this does NOT mean that hop is broken. Each router's
"time expired" reply during traceroute is OPTIONAL - many routers
(especially at large companies) are deliberately configured to stay
silent for security reasons (avoiding revealing internal network
layout), while still correctly forwarding real traffic onward. Proven
by the fact that traceroute still successfully reached the final
destination despite 9 silent hops along the way. Lesson: silence does
not always mean broken - sometimes it just means "this thing chose not
to respond to this specific kind of probe."

### tcpdump - Capturing Real Live Packets (strongest possible evidence)
Real incident encountered: first two attempts to capture a NEW
connection's handshake failed - captured output only showed ongoing
traffic from the ALREADY-ESTABLISHED SSH session in use, not a new
connection, because (a) no second SSH session was actually opened, and
(b) a race condition where nc's near-instant connect/disconnect
completed before tcpdump (started in the background) was fully ready
to capture.

Fixed by: starting tcpdump first, adding an explicit sleep to guarantee
it was ready, watching the correct interface (lo for loopback traffic,
not ens5), then firing nc separately.

Captured a COMPLETE real TCP 3-way handshake:
1. Flags [S] (SYN only) - client (ephemeral port 42220) to server
   port 22: "are you there?"
2. Flags [S.] (SYN+ACK) - server to client: "yes, heard you, and here
   is my own request back"
3. Flags [.] (ACK only) - client to server: "confirmed, begin"

Followed immediately by connection teardown (Flags [F] = graceful
finish request, Flags [R] = reset/abrupt termination) since nc -zv
was only testing reachability, not sending real data.

Confirms two things directly with real evidence: (1) the exact 3-step
handshake sequence documented in P03 actually happens exactly as
described, and (2) the ephemeral port (42220, a new random number each
run) matches the exact behavior predicted all the way back in the
very first P01 exercise ("it gives new one").

### Why This Matters Going Forward
The 3-layer failure model (Security Group -> binding -> application)
is the exact systematic diagnostic sequence for M04-P11 through P13.
tcpdump is the strongest possible evidence tool for proving whether
traffic is even arriving at a machine, which will be critical for
unguided RCA work in P20-P21.

### Key Takeaway
ss -tuln reveals what is listening and on which interface. nc gives
fast reachability answers without a full HTTP request. traceroute maps
the path traffic takes and silence at a hop does not necessarily mean
broken. tcpdump provides direct, undeniable proof of what is actually
happening on the wire - including a live-captured proof of the TCP
handshake theory from P03.

## M04-P06 - Install and Configure Nginx as a Reverse Proxy in Front of a Flask App

### The Core Idea
Nginx acts as the "receptionist" (from the P01 analogy) - the outside
world only ever talks to Nginx (port 80, the standard expected port),
and Nginx quietly forwards requests internally to the actual app
(Flask, on its own internal port), which the outside world never
needs to know about directly.

### Why Flask Binds to 127.0.0.1, Not 0.0.0.0 (Defense in Depth)
Once Nginx handles all outside traffic, the ONLY thing that needs to
reach Flask directly is Nginx itself - and both run on the same
machine, so loopback (127.0.0.1) is sufficient. Locking Flask to
127.0.0.1 means nobody can bypass Nginx and hit Flask directly from
the outside, even if they somehow knew the internal port - enforcing
"the only path in MUST go through Nginx." This is a real production
security pattern called defense in depth, directly using the binding
concept from P01.

Contrast: Nginx itself binds to 0.0.0.0:80, because ITS job is to
accept traffic from outside. Same binding concept, opposite
requirement, based on each service's actual role.

### Real Incident: Duplicate Flask Process on Port 5000
First attempt to start Flask failed with "Address already in use."
Investigated with `ss -tuln | grep 5000` + `ps aux | grep app.py`
rather than assuming - found TWO python3 app.py processes had been
started (one from an earlier command, unnoticed). The first (already
running) instance was correctly answering curl requests, while the
second correctly failed to bind (OS prevents two processes listening
on the same port+interface). Fixed by killing the stray process and
restarting cleanly with exactly one instance.

### Nginx Config - Reverse Proxy Block
File: /etc/nginx/sites-available/flask-proxy (symlinked into
sites-enabled/)

server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}

proxy_pass http://127.0.0.1:5000; is the actual forwarding line.
Important: NGINX itself is the one making this request to Flask, not
the original outside visitor - Nginx receives the external request on
0.0.0.0:80, then acts as its own client to open a SEPARATE connection
to Flask via loopback. Flask sees the request as coming from 127.0.0.1
because it genuinely is, from Nginx's perspective - the original
outside visitor never touches Flask directly.

### Real Incident: Config Conflict (default vs flask-proxy)
`sudo nginx -t` produced a warning: "conflicting server name '_' on
0.0.0.0:80, ignored" - both the default Nginx config AND the new
flask-proxy config used server_name _; (generic catch-all) on the
same port. Verified which one Nginx was actually using via
`ls -la /etc/nginx/sites-enabled/` and `sudo nginx -T | grep -A2
server_name` rather than guessing - confirmed the OLDER config
(default, created first) was winning, which explained why curl was
still showing the default "Welcome to nginx!" page instead of the
Flask response.

Fix: disabled (did not delete) the default site by removing only its
symlink from sites-enabled/, keeping the original file in
sites-available/ for reference:
sudo rm /etc/nginx/sites-enabled/default

### nginx -t - Why Validate Before Reloading
nginx -t checks config file syntax WITHOUT actually applying or
disrupting the running service - catches typos/mistakes safely before
a real reload. Standard production habit: always validate before
reloading.

### reload vs restart - Zero Downtime Principle
reload: tells the already-running Nginx process to re-read its config
and apply changes gracefully - existing connections finish normally,
new connections immediately use the new config. Zero downtime.

restart: fully stops the process, then starts a new one - a real,
however brief, gap where connections fail. Should be avoided for
routine config changes whenever the service supports a graceful
reload (Nginx does).

This is directly relevant to the "zero downtime deployment" Manager
Task later in this module (M04-P17/P18).

### Real Incident: Security Group Blocking External Access
After fixing the Nginx config conflict, curl from the SERVER itself
(127.0.0.1) succeeded correctly. But accessing http://<public-ip> from
an external browser produced "took too long to respond" - a TIMEOUT,
not a refused error.

Applied the P05 3-layer model directly: since Nginx was confirmed
working locally (ruling out binding/application layers), the only
remaining layer outside the EC2 instance entirely is the Security
Group - the outermost gate. Verified in the AWS console: port 80 had
NO inbound rule (only port 22/SSH was allowed). Added an inbound rule
for port 80, re-tested from the external browser - succeeded
immediately, receiving the real Flask response through the full chain.

This is a genuine, real-world confirmation of the 3-layer model built
in P05: Security Group (was blocking = timeout) -> binding (Nginx
0.0.0.0, Flask 127.0.0.1, both correct) -> application (Flask running
correctly) - working outside-in identified the actual root cause
directly, not by guessing.

### Why This Matters Going Forward
This exact "works locally but times out externally -> check Security
Group first" pattern is precisely what M04-P11 (Security Group
incident) and M04-P13 (502 Bad Gateway incident) will test formally -
this problem was effectively a live, unscripted version of that same
incident type.

### Key Takeaway
A reverse proxy works by having Nginx (external-facing, 0.0.0.0)
forward requests to an internal-only app (Flask, 127.0.0.1) - the
outside world never talks to the app directly. Config conflicts
between multiple enabled sites are resolved by load order, not
merging, and must be explicitly checked for. Always validate config
with -t and prefer reload over restart for zero-downtime changes. When
something works locally but fails externally with a timeout, the
Security Group is the first thing to check, per the 3-layer model.

### Real Incident: Silent Config Bug - & Instead of $ in proxy_set_header
While saving a copy of the live Nginx config for the repo, discovered
the actual running config had a typo: proxy_set_header Host &host; and
X-Real-IP &remote_addr; (ampersand instead of dollar sign for Nginx
variables).

Critical finding: `nginx -t` did NOT catch this as an error. Reasoning:
Nginx variables use $ syntax (e.g. $host, $remote_addr) to mean "fill
in the real value dynamically per request." &host is not invalid
syntax to Nginx's parser - it is simply treated as a literal string.
So the config was 100% syntactically VALID, just functionally WRONG -
same "build succeeds but behavior is wrong" lesson as M03-P12, applied
to config instead of code.

Impact: Flask would have received the literal text "&host" as a
header value instead of the real hostname, and "&remote_addr" instead
of the visitor's real IP - meaning Flask could never actually tell who
the real visitor was, defeating the purpose of these headers entirely.

Also discovered: `curl -v` cannot verify this kind of bug, because it
only shows the CLIENT-to-NGINX conversation, not the separate
NGINX-to-FLASK conversation happening behind the scenes. Proper
verification required modifying the Flask app itself to echo back the
headers it actually received (request.headers.get(...)), proving the
fix with real evidence rather than trusting curl's client-side view.

Fixed by correcting to $host and $remote_addr, reloading Nginx, and
confirming via Flask's own echoed response: "Host=127.0.0.1,
X-Real-IP=127.0.0.1" (both correctly showing the real dynamic values
when tested locally - X-Real-IP would show the actual external IP
when tested from an outside client instead of the server itself).

### Key Lesson Added
A config passing `nginx -t` only proves syntax validity, not semantic
correctness. Testing must verify actual BEHAVIOR (what the destination
app really receives), not just that the reverse proxy responds with
a 200 - the response body/status can look completely fine while the
proxy is silently forwarding wrong or useless header data underneath.

### ufw vs iptables - The Real Relationship (gap identified and filled)
ufw does NOT replace or run alongside iptables as a separate system.
ufw is a HIGH-LEVEL ABSTRACTION - a simpler, human-friendly interface
that automatically generates and manages real, low-level iptables
rules underneath. Same actual enforcement engine, different level of
complexity to interact with.

Comparison - same rule, two ways:
ufw:      sudo ufw allow 22/tcp
iptables: sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT

The iptables version requires understanding chains, targets, and jump
syntax just to allow one port - ufw reduces this to near-plain-English,
which is why it exists ("Uncomplicated Firewall") despite iptables
already existing and doing the same job.

### Proof (verified live on this EC2)
Ran: sudo iptables -L -n
Found custom chains automatically created by ufw: ufw-before-input,
ufw-after-input, ufw-reject-input, ufw-track-input, etc. - direct,
real proof that ufw was silently managing actual iptables rules the
whole time, despite never running a single raw iptables command
directly.

Bonus finding: DOCKER-USER and DOCKER-FORWARD chains were also present
in the same output - Docker (from Module 03) also directly manipulates
iptables automatically for container networking. Real production
gotcha worth knowing: Docker and ufw both independently modify the
same underlying iptables system without coordinating with each other,
which can occasionally cause rule conflicts in real environments.

### Key Takeaway (added)
ufw = high-level abstraction. iptables = low-level engine actually
enforcing the rules. ufw generates real iptables rules automatically;
it does not replace iptables or work independently of it.

## M04-P08 - SSH Deep-Dive (Keys, Agent Forwarding, Config File, Troubleshooting)

### Public/Private Key Pairs - Why Two Keys Instead of One Shared Secret
Private key: stays only on your laptop, NEVER shared or uploaded
anywhere. Public key: safe to copy to any number of servers -
mathematically useless to an attacker without the matching private key
(asymmetric cryptography - cannot reverse a public key to derive the
private key).

CORRECTION made during this session: initially assumed that if one
server using a shared key pair gets compromised, all other servers
using the same key pair become vulnerable too. This is WRONG for the
realistic case. What a compromised server actually exposes is only
what it stores - the PUBLIC key sitting in ~/.ssh/authorized_keys.
Since a public key cannot be reverse-engineered into the private key,
compromising Server A gives an attacker nothing usable against Server
B, C, D, E, even if they all trust the identical key pair.

The ONLY real danger: the private key FILE ITSELF (the .pem on your
laptop) being stolen (e.g. malware, or accidentally committing it to a
public repo) - that is a completely separate event from any individual
server being hacked, and is genuinely the one thing that would
compromise every server using that key pair simultaneously.

Verified live: cat ~/.ssh/authorized_keys on the EC2 showed only the
public key (labeled "devops-blackbelt-lab-key", matching STATUS.md) -
confirmed safe to expose/paste anywhere, proving the concept directly.

### SSH Config File / MobaXterm Saved Sessions - Convenience, Not IP-Stability
~/.ssh/config (Linux/WSL/Git Bash) or MobaXterm's saved sessions (GUI)
both let you save a shortcut (key path + username + host) instead of
typing the full ssh -i ... command every time.

LIMITATION identified: neither solves the fact that this EC2's public
IP changes every time it's stopped/started (per STATUS.md) - the saved
HostName/Remote host field must still be manually updated each time.
Real production fix for this specific problem: an AWS Elastic IP
(static, unchanging) - out of scope for this networking module,
belongs to Module 05 (AWS).

### SSH Agent Forwarding - Real Investigation (assumption corrected)
Real use case: SSH from laptop into Server A, then from INSIDE Server
A, SSH into a second Server B - using the LAPTOP's private key,
without ever copying that key onto Server A's disk.

Initial incorrect assumption: assumed this must be how Git push to
GitHub worked from the EC2 in Module 02. INVESTIGATED rather than
accepted the assumption:
- ls -la ~/.ssh/ on EC2 showed only authorized_keys and known_hosts -
  NO private key file exists on this EC2 (rules out a separate
  EC2-generated key pair)
- echo $SSH_AUTH_SOCK returned empty, and ssh-add -l returned "Could
  not open a connection to your authentication agent" - agent
  forwarding is NOT currently active in this session
- git remote -v showed origin as https://github.com/... , NOT
  git@github.com:... (SSH) - CONFIRMED: Git authentication has never
  used SSH keys at all. It uses HTTPS with a Personal Access Token /
  cached credential helper - a completely separate auth mechanism.

Lesson: agent forwarding was never actually used in this setup. The
initial assumption was disproven with real command evidence rather
than accepted at face value - exactly the "verify, don't assume"
discipline this workbook is built around, applied here to catch an
incorrect premise in the teaching itself, not just an answer.

Checked MobaXterm's session settings: agent forwarding is not exposed
in the main Advanced SSH settings tab (X11-Forwarding is a DIFFERENT,
unrelated feature - forwards GUI apps, not SSH keys) - it lives inside
the "Expert SSH settings" button, and was never enabled, consistent
with all the command-line evidence above.

### Troubleshooting SSH Connection Failures - Applying the 3-Gate Model
Symptom: ssh: connect to host <ip> port 22: Connection timed out

Applying the P07 3-gate model: timeout = Gate 1 (Security Group) issue,
by definition - the request never reached the instance's OS at all.

Generalization identified: timeout does not reveal WHICH specific
Security Group problem exists - it could be (a) no inbound rule for
port 22 at all, (b) a rule exists but restricted to a specific IP/CIDR
range that no longer matches the current connecting IP (common real
scenario: dynamic ISP-assigned home IP changes over time), or (c) SG
somehow detached from the instance. All three produce the IDENTICAL
timeout symptom - the Security Group doesn't distinguish "no rule" from
"rule exists but doesn't match you." Determining which of the three
requires actually checking the AWS console directly; the symptom alone
only narrows it to "something about the Security Group," not to a
specific cause.

### Why This Matters Going Forward
This exact SG-IP-mismatch scenario (timeout despite previously-working
SSH) is a strong candidate root cause for M04-P12 (SSH connection
incident) later in this module - a genuinely common real-world trigger
that has nothing to do with the key pair or the instance itself being
broken.

### Key Takeaway
Public/private key security relies on asymmetric cryptography - a
compromised server only exposes the public key, which is harmless
without the private key; only the private key FILE itself must be
protected. Config file/saved-session shortcuts solve typing convenience,
not IP volatility - that needs an Elastic IP. Agent forwarding relays
a laptop's key through an intermediate server for further SSH hops,
but is a DIFFERENT mechanism from HTTPS-based Git authentication - the
two should not be assumed to be the same "it must have used my key
somehow" explanation. Timeout during SSH always implicates the
Security Group layer, but the specific cause among several
possibilities requires direct verification, not assumption.

## M04-P09 - Nginx Load Balancing (Round-Robin, Least-Connections, IP-Hash)

### Why Load Balancing Exists
Two distinct benefits from running multiple identical backend
instances behind Nginx instead of one:
1. PERFORMANCE (horizontal scaling) - spreads load across multiple
   instances so no single one gets overwhelmed, vs vertical scaling
   (making one instance more powerful)
2. AVAILABILITY - if one instance crashes, traffic continues flowing
   to the survivors instead of total outage

### DRY Principle Applied to Test Apps
app.py was refactored to accept the port as a command-line argument
(sys.argv[1]) instead of creating 3 separate hardcoded files. Reason:
one file to maintain - any bug fix or change automatically applies to
all instances, rather than needing the same edit repeated 3 times
across separate files (easy to fix 2 and forget the 3rd).

### upstream Block - The Core Mechanism
upstream flask_backend {
    server 127.0.0.1:5001;
    server 127.0.0.1:5002;
    server 127.0.0.1:5003;
}
"flask_backend" is NOT a real DNS hostname - it is an internal alias
name Nginx recognizes only within this config, scoped to the upstream
block directly above it. proxy_pass http://flask_backend; tells
Nginx "pick one server from this named group" rather than pointing to
one fixed server.

### Round-Robin (Nginx default, no directive needed)
Cycles through the server list in strict order: 1, 2, 3, 1, 2, 3...

REAL INCIDENT/LESSON: first test (6 requests fired near-instantly via
a tight for loop) showed a seemingly broken pattern (5001, 5001, 5002,
5003, 5001, 5002) - NOT actually broken. All 6 requests shared the
IDENTICAL timestamp (fired in the same second), meaning the test
itself was too fast to observe true cycling order due to
logging/buffering timing artifacts. Re-tested with `sleep 1` between
each request - produced a clean, perfect repeating cycle (5003, 5001,
5002, 5003, 5001, 5002). Lesson: evidence that looks wrong does not
always mean the system is broken - sometimes it means the TEST METHOD
is too imprecise to observe the real behavior correctly.

### Least-Connections (least_conn directive)
Tracks ACTIVE, in-progress connections per backend and routes new
requests to whichever backend currently has the FEWEST - unlike
round-robin's blind cycling, which gives every server an equal COUNT
of requests but not necessarily equal ACTUAL LOAD (a server stuck on
one slow request still gets new requests forced onto it under
round-robin).

Correctly identified before testing that least_conn's effect is
INVISIBLE with fast, near-identical response times - the difference
only appears when connection durations vary meaningfully.

Proved with real evidence: deliberately made port 5001 artificially
slow (3 second delay) via a modified app_slow.py. Fired 9 PARALLEL
requests (curl ... & for backgrounding, not sequential). Result:
5002 got 4 requests, 5003 got 3 requests, port 5001 (the slow one)
got only 2 - and those 2 requests on port 5001 were clearly delayed
(timestamped 3 full seconds after all others completed), proving
least_conn correctly avoided piling more traffic onto the already-busy
slow server.

### IP-Hash (ip_hash directive) - Sticky Sessions
Real-world problem this solves: an app storing session data (e.g.
shopping cart) IN MEMORY on a specific backend instance, not in a
shared database. If round-robin bounces a user's second request to a
DIFFERENT backend than their first, that new backend has never seen
their session data - appears as data loss/inconsistent state to the
user (e.g. their cart appears empty).

ip_hash fixes this by hashing the VISITOR'S SOURCE IP through a hash
function to consistently select the SAME backend for that IP every
time - "sticky sessions." Note: which specific server a given IP
hashes to is effectively arbitrary/unpredictable by inspection - the
only guaranteed property is CONSISTENCY (same IP always gets same
server), not any particular intuitive mapping.

Proved with real evidence: 5 sequential requests from the same source
IP all landed on port 5003 every single time, with zero variation -
confirmed genuine stickiness.

### Real Incident: Background Flask Processes Died Silently
While testing ip_hash, all 5 requests returned 502 Bad Gateway.
Diagnosed using an extended version of the 3-gate model: a 502
specifically means NGINX ITSELF responded successfully (ruling out
Security Group/ufw/Nginx crash) but Nginx's attempt to reach ITS
backend failed - meaning the problem was one layer deeper than the
3-gate model's Gate 3, specifically inside what Gate 3 was supposed to
reach.

Investigated with real commands rather than assuming: `ss -tuln` and
`ps aux | grep app_slow` both confirmed ALL THREE backend instances
were dead - none were listening, no processes existed. Root cause:
background processes started with `&` are tied to the shell session
that launched them; the session had ended in the meantime (terminal
behavior, similar risk category to any long-running background job
without nohup/screen/tmux), killing all 3 Flask processes along with
it.

Fixed by restarting all 3 instances fresh, re-verified with ss -tuln
before retesting - real proof followed immediately (consistent 5003
responses for ip_hash).

### Automatic Failover with ip_hash
Killed ONLY port 5003 (the instance the current IP was hashed to)
while leaving 5001 and 5002 alive. Verified dead via ss -tuln (no
output for port 5003). Re-tested: Nginx CORRECTLY detected the dead
backend and automatically rerouted to port 5002 - no 502s, no manual
intervention. ip_hash's stickiness then re-established itself onto
the new server (5002), consistently, for subsequent requests.

### Why This Matters Going Forward
The 502 Bad Gateway incident encountered here (backend died, Nginx
correctly reported it) is a live, unscripted preview of M04-P13
(dedicated 502 Bad Gateway incident) - already practiced the exact
diagnostic reasoning needed there. least_conn and ip_hash tradeoffs
are directly relevant to M04-P16 (Manager Task: reduce latency) and
system design interview questions about load balancer selection.

### Key Takeaway
Round-robin = fair by request COUNT, not by actual load. Least-conn =
fair by actual current load, requires varying request durations to
matter. IP-hash = sacrifices load-balancing fairness entirely in favor
of session consistency for a given visitor. Nginx automatically
detects and routes around dead backends regardless of which algorithm
is active. Evidence that looks wrong should be investigated for test
methodology issues before assuming the system itself is broken.

## M04-P10 - TLS/SSL Fundamentals (Self-Signed Cert, HTTPS Termination at Nginx)

### Why HTTPS/TLS Exists
Plain HTTP sends everything (headers, form data, passwords) as
READABLE PLAIN TEXT - directly provable with tcpdump (P05), same tool
that showed the SSH banner. Anyone with network access along the path
can capture and read it. TLS encrypts the actual content so captured
packets are unreadable garbage without the correct key.

### Why Part of Every Secure Handshake Is Unavoidably Plain Text
Two sides must first AGREE on how to encrypt (algorithm, protocol
version) before any encryption can begin - this negotiation step
cannot itself be encrypted (chicken-and-egg problem). Directly
observed in P05's SSH capture: the "SSH-2.0-OpenSSH..." banner was
plain text because it happens BEFORE encryption is established;
everything after (actual commands) is encrypted. TLS has an
equivalent unavoidably-visible negotiation step.

### Why TLS Uses BOTH Asymmetric AND Symmetric Encryption
Asymmetric (like SSH's key pairs, P08) is mathematically expensive/
slow - fine for a one-time handshake, too slow for continuous bulk
data transfer. Symmetric uses one shared key, fast, but requires BOTH
sides to safely have the same secret without an eavesdropper
capturing it in transit.

The actual mechanism: client encrypts a symmetric key using the
SERVER'S PUBLIC key. Only the server's PRIVATE key can decrypt it
(same asymmetric guarantee as SSH - cannot reverse public into
private). An eavesdropper capturing this exchange sees only scrambled
data and CANNOT extract the symmetric key without the private key.
Once safely exchanged, both sides switch to fast symmetric encryption
for the rest of the session.

CONFIRMED with real evidence via curl -v handshake output:
"SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384 /
X25519MLKEM768 / RSASSA-PSS"
- RSASSA-PSS = asymmetric (RSA), used briefly for identity/handshake
- X25519MLKEM768 = key exchange mechanism (includes a post-quantum-
  resistant component)
- TLS_AES_256_GCM_SHA384 = symmetric cipher (AES) used for the actual
  HTTP response that followed

### Generating a Self-Signed Certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/selfsigned.key \
  -out /etc/nginx/ssl/selfsigned.crt \
  -subj "/CN=<ec2-public-ip>"

Verified file permissions automatically enforced by OpenSSL:
selfsigned.crt (public) = -rw-r--r-- (world-readable)
selfsigned.key (private) = -rw------- (root only)
Same protective principle as SSH private key files - enforced
automatically at the OS permission level.

### Nginx HTTPS Termination Config
Added a SECOND server block (listen 443 ssl) alongside the existing
port 80 block, both pointing to the SAME upstream flask_backend:

server {
    listen 443 ssl;
    server_name _;
    ssl_certificate /etc/nginx/ssl/selfsigned.crt;
    ssl_certificate_key /etc/nginx/ssl/selfsigned.key;
    location / {
        proxy_pass http://flask_backend;
        ...
    }
}

### "HTTPS Termination at Nginx" - What It Actually Means
Nginx is where the encrypted (HTTPS) conversation ENDS - it decrypts
incoming traffic, then forwards the request to Flask over PLAIN HTTP
via loopback (127.0.0.1). This is correct and safe because loopback
traffic never leaves the machine - there is no network segment for an
attacker to intercept, unlike the public internet hop between the
visitor and Nginx. Encryption protects data crossing physically
separate machines/networks; it is not needed for same-machine
loopback communication. (Note: in real multi-server production
setups, some environments DO encrypt internal hops too - e.g. mutual
TLS in a service mesh, relevant to Module 06's Istio coverage - but
not needed here since Nginx and Flask share one machine.)

### New Port Requires BOTH Gates Updated (3-gate model applied)
Port 443 required explicit rules in BOTH layers, neither automatic:
- Security Group (AWS console) - added HTTPS/443 inbound rule
- ufw (OS firewall) - sudo ufw allow 443/tcp (confirmed via ufw
  status verbose showing 443/tcp ALLOW IN)
Nginx listening on a new port does not automatically grant access
through either outer gate - both had to be explicitly configured,
consistent with the P07 3-gate model.

### -k / --insecure Flag
Without -k, curl treats an unverifiable (self-signed) certificate as
a HARD FAILURE, refusing to connect - not just a warning. This is
deliberate: curl cannot distinguish "my own test certificate" from
"an attacker's fake certificate" (man-in-the-middle attack). -k tells
curl to proceed anyway despite failed verification - appropriate only
when the certificate is KNOWN and trusted by the user directly (own
lab/test environment), never against an unknown production site.

### Self-Signed vs CA-Signed - The Real Distinction
Verified via curl -v output: subject: CN=<ip> and issuer: CN=<ip> are
IDENTICAL - the literal definition of "self-signed": the certificate
vouches for itself rather than being vouched for by an independent,
trusted Certificate Authority (CA).

CRITICAL DISTINCTION - TLS solves TWO separate problems, not one:
1. ENCRYPTION (privacy) - self-signed certs handle this completely
   fine, PROVEN by real evidence (TLS_AES_256_GCM_SHA384 genuinely
   negotiated and used for this session)
2. IDENTITY VERIFICATION (authenticity - "am I really talking to the
   real server, not an impostor?") - self-signed certs provide ZERO
   protection here, since ANYONE can self-sign a certificate claiming
   to be ANY domain

Real-world attack self-signed certs cannot prevent: an attacker
intercepting a connection (e.g. on public WiFi) can generate their
OWN self-signed certificate impersonating a real site (e.g.
yourbank.com). If browsers trusted any self-signed cert silently, the
victim would have a perfectly ENCRYPTED connection directly to the
attacker - encryption alone is not enough without verified identity.
A real CA only issues a certificate for a domain after verifying the
requester genuinely controls it, which is what browsers actually
check for and warn about when missing.

### Why Self-Signed Is Acceptable Here Specifically
The identity-verification threat model only matters when there is an
untrusted public audience who needs reassurance they are reaching the
real server, not an impostor. For this lab EC2, the only person
connecting is the person who built it and already knows/controls both
ends - there is no one else to trick. Self-signed is standard,
accepted practice for internal tools, local development, and lab/test
environments; CA-signed certificates (e.g. via free automated services
like Let's Encrypt) are required once real, untrusted public visitors
are involved - directly relevant to M04-P17/P18 (Manager Task: set up
HTTPS before launch) later in this module.

### Why This Matters Going Forward
The encryption-vs-identity-verification distinction is a strong,
precise interview answer for "why does HTTPS show a warning for
self-signed certificates." HTTPS termination at Nginx is the standard
pattern used again in Module 06 (Kubernetes Ingress) and will reappear
directly in M04-P17 (Manager Task: HTTPS before launch), this time
with a real, CA-signed approach.

### Key Takeaway
TLS solves encryption (privacy) AND identity verification (authenticity)
- self-signed certificates provide only the first, which is why
browsers warn on them; CA-signed certificates are required once real,
untrusted visitors are involved. HTTPS termination at Nginx means
Nginx decrypts external traffic and forwards plain HTTP internally
over loopback, which is safe since that hop never leaves the machine.
New ports always require updates to BOTH the Security Group and ufw,
independently - neither is automatic just because Nginx is listening.

## M04-P11 - Debug Challenge: Broken Nginx Config

### Real Incident: Debug Challenge Accidentally Overwrote Live Config
The debug challenge was initially set up by editing the REAL, live
/etc/nginx/sites-available/flask-proxy directly - overwriting the
working P09/P10 config with the deliberately-broken challenge config.
CORRECTED by creating a separate, isolated file
(networking-lab/broken-nginx-challenge.conf) for the debug exercise
instead, leaving the live config untouched. Lesson: debug/practice
exercises should always use throwaway files, never overwrite a known-
working live config directly.

### Real Incident (recurring): Background Flask Processes Died Again
While verifying the live config was intact, curl returned 502 Bad
Gateway despite nginx -t passing. Investigated with ss -tuln and
ps aux (same method as P09) - confirmed all 3 Flask instances
(5001/5002/5003) were dead again, same root cause as P09: processes
started with `&` are tied to the shell session and die when it ends.

FIXED PROPERLY this time using nohup instead of just `&`:
nohup python3 app.py 5001 > /tmp/flask-5001.log 2>&1 &
nohup and output redirection allow the process to survive even after
the terminal session/SSH connection that started it ends - solving
the ROOT CAUSE of this recurring incident rather than just restarting
the same fragile way a third time.

### Bugs Found by Careful Reading Alone (before running nginx -t)
Applied the pattern "every Nginx directive line must end in a
semicolon" mechanically across the whole file:

Bug #1: Missing semicolon - `server 127.0.0.1:5000` (upstream block)
Bug #2: Missing semicolon - `access_log off` (/health location)
Bug #3: Missing semicolon - `ssl_certificate_key ...selfsigned.key`
Bug #4: Missing semicolon - `proxy_pass http://flask_backend`
        (HTTPS server block, / location)

All 4 are pure syntax errors - confirmed nginx -t failed before
fixing them, and passed cleanly ("syntax is ok", "test is successful")
immediately after fixing all 4, with no further syntax issues
revealed - proving the manual read-through was thorough and accurate.

### Bugs Found Only by Testing Actual Behavior (nginx -t passed, still wrong)

Bug #5: upstream flask_backend pointed to port 5000 - NO Flask
instance has run on port 5000 since P09 (real instances are on
5001/5002/5003). Verified via ss -tuln | grep 5000 returning BLANK
(no listener). This is syntactically perfect but functionally wrong -
same "valid but wrong" category as the &host bug from P06. Impact:
every single request through this config would return 502 Bad
Gateway, since Nginx has nothing valid to actually forward to.

Bug #6: The /health location block correctly configures ROUTING and
LOGGING (access_log off) at the Nginx level, but Flask itself (per
app.py, verified via cat) has NO /health route defined - only /.
Nginx forwarding a request to a route Flask doesn't recognize does
NOT produce "refused" or "timeout" - CORRECTED assumption during this
exercise: Flask is alive and responds normally, just with a 404 Not
Found, which is a fully successful network transaction at the
connectivity level (all 3 gates from P07 worked correctly) - 404 is
an APPLICATION-level outcome, not a connectivity failure.

Testing note: Bug #5 initially MASKED Bug #6 - since the broken
upstream port affected ALL routes equally, testing /health returned
502 (Bug #5's symptom) rather than clearly revealing the missing-route
issue underneath. Had to fix Bug #5 first, then re-test /health in
isolation to properly confirm Bug #6 as a genuinely separate issue.
Lesson: bugs can mask each other - fix and re-verify one at a time,
don't assume a single test result means only one thing is wrong.

### Requirement Check: HTTP to HTTPS Redirect
location / {
    return 301 https://$host$request_uri;
}
This logic is actually CORRECT as written - a 301 permanent redirect
using the request's own host and original URI, correctly upgrading
any HTTP request to HTTPS. No bug found here after review - a good
reminder that not every block in a "broken config" exercise is
necessarily broken; some correctly-written blocks should be
recognized and left alone rather than needlessly "fixed."

### Why This Matters Going Forward
This exercise combined syntax errors (caught mechanically via the
semicolon pattern + nginx -t) with logic errors (caught only via
actual behavioral testing) - directly mirroring the real incident
categories coming up in M04-P12 (SSH) and M04-P13 (502 Bad Gateway).
The masking-bugs lesson (Bug #5 hiding Bug #6) is directly relevant to
real production debugging, where multiple simultaneous issues are
common and testing one fix at a time is the only reliable way to
isolate each one.

### Key Takeaway
nginx -t only validates syntax, never behavior - passing it is a
necessary but not sufficient condition for a config being correct.
Systematic reading (checking for a consistent pattern like missing
semicolons) can catch real bugs before ever running a tool. Logic
bugs require testing actual behavior against the STATED INTENT (what
the teammate said they wanted), not just what the config appears to
do at a glance. Bugs can mask each other - always re-test after each
individual fix, not just once at the end.

## M04-P12 - Real Incident (Pre-Exercise): EC2 Reboot Killed nohup Processes

### What Happened
Before the planned Security Group exercise even began, baseline check
(curl to both HTTP and HTTPS) returned 502 Bad Gateway. Investigated
with ss -tuln and ps aux (same method as P09/P11) - confirmed ALL 3
Flask instances were dead, DESPITE having used nohup specifically to
prevent this in P11.

### Root Cause - A New Failure Mode, Different From P09/P11
Checked `uptime` - showed "up 10 min," revealing the EC2 instance
itself had rebooted (stopped/started) recently. This is a
DIFFERENT failure mode than the earlier session-ending incidents:

- P09/P11 cause: shell session ended -> `&` background jobs died
  (nohup WOULD have prevented this)
- P12 cause: the ENTIRE MACHINE rebooted -> nohup does NOT protect
  against this, because a full OS reboot wipes ALL running processes
  from memory regardless of how they were started

CORRECTED UNDERSTANDING: nohup only protects against the shell/SSH
session ending. It does NOT make a process durable across a full
machine reboot.

### Confirmed via Contrast with Nginx
sudo systemctl status nginx showed Nginx WAS already back up and
running automatically since the reboot, with zero manual
intervention - because Nginx is registered as a real systemd service
("Loaded: ... enabled") which automatically starts on every boot, a
fundamentally more robust mechanism than a manually-run nohup
background job.

### Fix
Manually restarted all 3 Flask instances again via nohup (correct
practice for surviving session disconnects specifically, just not
full reboots):
nohup python3 app.py 5001 > /tmp/flask-5001.log 2>&1 &
(repeated for 5002, 5003)

### Why This Matters Going Forward
This is direct, real foreshadowing of why production systems never
rely on manually-run background processes at all - proper process
supervision (systemd services, or later in this workbook: Docker
restart policies in Module 03, and Kubernetes' entire self-healing
design in Module 06) is what actually survives both session endings
AND full reboots automatically. This is a genuine real-world gap
between "lab/practice setup" and "production-grade setup," worth
remembering directly for system design interview questions about
service resilience.

### Key Takeaway
nohup solves session-ending, not machine-rebooting. Only a real
process supervisor (systemd, Docker restart policies, Kubernetes)
survives a full reboot automatically. Always check `uptime` when
investigating an unexplained "everything that was running is now
dead" scenario - a machine reboot is a distinct root cause from a
session ending, even though both can produce the identical symptom
(background processes gone).

## M04-P12 - Incident: "Site Is Down" - Security Group Misconfiguration

### RCA Report

**Problem:** Site completely unreachable from external customers/
browsers. Reported via teammate message: "hangs and eventually times
out," confirmed independently by a customer complaint on social media.

**Impact:** Complete external outage - no customer could reach the
site via HTTP. Internal/local access (from the EC2 itself) was
unaffected, meaning the application layer itself was never at risk -
this was purely a network-boundary issue.

**Timeline:**
- Teammate reports site down, describes symptom as "hangs then times
  out" (a specific, diagnostically useful detail, not just "it's down")
- Diagnosed locally first: curl http://127.0.0.1 from the EC2 itself
  SUCCEEDED - confirmed Nginx and Flask backend both healthy
- Diagnosed externally: curl/browser from an actual separate laptop
  to the public IP TIMED OUT - confirmed matching the reported symptom
- Applied the P07 3-gate model: local success + external timeout can
  ONLY mean a Gate 1 (Security Group) issue - Gates 2/3 would produce
  "refused," not timeout, and were already ruled out by the successful
  local test
- Verified directly in AWS Console: Security Group inbound rules had
  NO rule for port 80 at all
- Added inbound rule: HTTP, port 80, source 0.0.0.0/0
- Re-verified from the same external laptop: request succeeded,
  received the real Flask response

**Root Cause:** The Security Group's inbound rules did not include
port 80 at all. Without an explicit allow rule, AWS's default-deny
behavior silently dropped every external request at the network
boundary, before it ever reached the EC2 instance's OS - producing a
timeout, not a refused connection, consistent with the P07 model.

**Resolution:** Added an inbound rule to the Security Group allowing
HTTP (port 80) from anywhere (0.0.0.0/0), matching the same
configuration originally set up in P06.

**Preventive Action:** Security Group changes are high-impact and
should be reviewed/audited before/after any infrastructure cleanup
work, since a single accidental rule removal causes a complete,
silent outage with no error logged anywhere on the instance itself
(Nginx and Flask logs showed nothing wrong, because they never even
received the requests). Consider documenting required Security Group
rules explicitly (e.g. in this very NOTES.md or a dedicated
infrastructure-as-code file) so a misconfiguration can be quickly
diffed against a known-good baseline instead of manually reasoned
about live.

**Lessons Learned:** The diagnostic value of TESTING FROM TWO VANTAGE
POINTS (local vs external) cannot be overstated - it immediately
isolates whether a problem is Security-Group-level (only external
fails) versus application/OS-level (both local and external fail).
This single comparison collapsed the entire 3-gate model into one
clear answer without needing to check ufw or Nginx/Flask logs at all.
Also reinforced: a customer/teammate's exact WORDING of a symptom
("hangs then times out" vs "immediately says connection refused") is
real diagnostic information, not just noise - it should be captured
and used, not glossed over, before starting investigation.

### Why This Matters Going Forward
This is the canonical real-world pattern for the ENTIRE 3-gate model
built across P07-P11: local success + external timeout = Security
Group, every time, with no exceptions, as long as ufw/app-level issues
have been ruled out via the local test first. This exact diagnostic
sequence (local test -> external test -> compare -> conclude which
gate) is a strong, reusable interview answer for "how would you debug
a site that's down."

### Key Takeaway
A local curl success + an external timeout is definitive evidence of
a Security-Group-level problem, requiring no further investigation of
the application or OS layers. AWS Security Group misconfigurations
produce ZERO error logs on the instance itself, since the traffic
never arrives - the only way to catch them is through this local-vs-
external comparison test, not by reading application logs.

## M04-P13 - Incident: SSH Connection Refused/Timeout - Diagnosing Across 3 Layers

### Safety Note (real decision made this session)
Originally planned to deliberately block SSH at both Security Group
AND ufw simultaneously to practice diagnosis hands-on. DECIDED AGAINST
this due to genuine lockout risk if anything went wrong mid-exercise
(would require AWS Session Manager/Serial Console to recover, per the
P08 warning). Worked through the diagnostic reasoning via structured
scenarios instead, without risking the live, working session. Real
lesson: recognizing when a "hands-on" exercise carries disproportionate
risk relative to its learning value, and choosing a safer method to
get the same understanding, is itself a valid engineering judgment
call - not every concept needs to be broken live to be learned properly.

### Scenario 1: "Connection timed out"
Per the P07 3-gate model, timeout can ONLY happen at Gate 1 (Security
Group) - this single symptom immediately rules out ufw (Gate 2) and
the SSH service itself (Gate 3) entirely, since both of those would
produce "refused," not silence. Diagnostic action: go straight to the
AWS Security Group console, no need to check ufw or sshd status at
all. (Concretely diagnosed and fixed for HTTP/HTTPS in M04-P12 - same
model applies identically to SSH/port 22.)

### Scenario 2: "Connection refused"
Refused rules OUT Gate 1 (Security Group let it through) - the
problem is Gate 2 (ufw) or Gate 3 (sshd itself). Correct diagnostic
order, using the MOST SPECIFIC/DECISIVE check first:

1. ss -tuln | grep :22 - checks Gate 3 directly (is sshd even running
   and listening at all)
   - If NOTHING shows: sshd itself is not running - this IS the root
     cause. Checking ufw at this point is WASTED EFFORT, because there
     is no destination for traffic to reach regardless of firewall
     rules - the problem is already fully identified. Fix: restart
     sshd (sudo systemctl restart ssh), not touch ufw at all.
   - If sshd IS shown listening, but "refused" still occurs: THEN
     check ufw status verbose - this narrows it specifically to Gate 2
     (ufw actively blocking, despite the app being alive).

### General Diagnostic Principle (identified this session)
Always check from the MOST SPECIFIC, MOST DECISIVE layer first when
multiple layers could explain the same symptom - a single check
(ss -tuln) can sometimes make an entire OTHER category of
investigation (ufw rules) irrelevant, by confirming the failure
happened at a completely different, more fundamental level first.
Checking things in the wrong order wastes time investigating a layer
that was never actually the problem.

### Complete 3-Layer SSH Diagnostic Summary (this problem's core deliverable)
| Symptom  | Gate Responsible      | First Diagnostic Command          |
|----------|----------------------|-------------------------------------|
| Timeout  | Gate 1 (Security Group) | Check AWS console directly (no local command can diagnose this - it never reaches the instance) |
| Refused, nothing listening | Gate 3 (sshd itself) | ss -tuln \| grep :22 - shows nothing |
| Refused, something IS listening | Gate 2 (ufw)  | sudo ufw status verbose - shows a deny/no-allow rule |

### Why This Matters Going Forward
This exact 3-row diagnostic table generalizes to EVERY service in this
module, not just SSH - the same logic applies identically to Nginx
(port 80/443), Flask, or any future service in later modules (Jenkins,
Kubernetes NodePorts, etc.). This is a strong, structured interview
answer for "walk me through how you'd debug a connection failure."

### Key Takeaway
Timeout vs refused immediately narrows a connection failure to either
Gate 1 alone, or Gates 2/3 - and for refused specifically, checking
"is anything even listening" (ss -tuln) BEFORE checking firewall rules
(ufw) is the more efficient, more decisive diagnostic order, since a
dead service makes firewall rules irrelevant to check at all.

## M04-P14 - Incident: Nginx 502 Bad Gateway - Upstream App Crashed

### RCA Report

**Problem:** Customers report intermittent 502 Bad Gateway errors -
"sometimes it works, sometimes it doesn't, seems random."

**Impact:** Partial, inconsistent service degradation - unlike P12
(total outage) or P13 (SSH access), this scenario specifically
explores PARTIAL failure across a load-balanced backend pool, where
some requests succeed and others fail depending on routing.

**Investigation Timeline (built from first principles, with real
testing at each stage):**

1. Built a deliberately buggy route (ZeroDivisionError, unhandled
   exception) - tested directly against Flask (bypassing Nginx) and
   discovered a CORRECTED assumption: an unhandled exception in ONE
   route does NOT crash the entire Flask process. Flask's dev server
   catches it per-request and returns a 500 Internal Server Error,
   while the process itself keeps running normally for all other
   requests (proven live: curl to / succeeded immediately after
   triggering the crash on /divide).

2. Realized this meant a per-request exception can NEVER produce a
   real 502 - only a 500, since the process never actually dies. A
   502 specifically requires the ENTIRE backend process to become
   unreachable (crashed/hung), not just one bad request being caught
   and wrapped into an error response.

3. Built a genuinely process-killing route using os._exit(1) - bypasses
   Flask's exception handling entirely (OS-level immediate termination,
   no chance to generate any response). Verified directly: curl to
   this route returned NO response at all, curl exit code 7 ("failed
   to connect"), and ss -tuln confirmed the port had zero listener
   immediately after - genuine, complete process death.

4. Tested this dead backend through Nginx (round-robin across 3
   backends, one now dead). PREDICTED a mix of 200s and 502s.
   ACTUAL REAL RESULT: all 200s, ZERO 502s across 6 requests -
   prediction was WRONG, investigated rather than dismissed.

5. Root cause of the surprising result: NGINX HAS BUILT-IN PASSIVE
   HEALTH CHECKING. The first time Nginx tries to reach a backend and
   fails, it automatically marks that backend temporarily unavailable
   and stops routing new traffic to it, retrying later. This is the
   SAME mechanism already proven in P09's ip_hash failover test
   (killing port 5003 there) - applied here to round-robin instead.
   A 502 would only be visible for the very first request(s) that
   happen to hit the backend right at the moment it dies - after
   that, Nginx silently routes around it.

6. Reasoned through the ACTUAL likely cause of genuinely ONGOING,
   intermittent 502s (not just a one-time dead backend, which
   self-heals into consistent success as shown above): a backend
   stuck in a CRASH LOOP - repeatedly restarting, briefly appearing
   healthy again (Nginx re-marks it available), receiving new traffic,
   crashing again. This produces a genuinely unpredictable, "sometimes
   works sometimes doesn't" pattern from the outside, unlike a single
   permanently-dead backend. Directly connects to "CrashLoopBackOff,"
   a named production incident type in STATUS.md, to be revisited
   formally in Module 06 (Kubernetes).

**Root Cause (of the ORIGINAL scenario, as diagnosed):** Intermittent
502s are best explained by a backend in a crash-loop cycle, not a
single permanently dead instance - Nginx's automatic health checking
means a truly dead backend quickly stops causing visible errors at all,
while a repeatedly-crashing-and-restarting backend continues producing
sporadic failures indefinitely as it cycles between healthy and dead.

**Resolution (in this lab):** Restored the healthy, non-crashing
app.py on all 3 ports, re-enabled ip_hash. Real production resolution
for a genuine crash loop would require investigating and fixing the
underlying application bug causing the repeated crashes - Nginx-level
failover only masks the symptom, it doesn't fix the actual defect.

**Preventive Action:** Application-level error handling (500) is not a
substitute for process-level resilience against catastrophic failures
(502) - both categories of failure need separate handling: catch
exceptions gracefully within routes where possible (preventing 500s
from being confusing/unhelpful), AND ensure a process supervisor
(systemd, Docker restart policies, or Kubernetes) automatically
restarts genuinely crashed processes, converting "permanently down"
into "briefly down, then healthy again."

**Lessons Learned:** A wrong prediction, when investigated rather than
dismissed, revealed a genuinely important and previously-undocumented
mechanism (Nginx's passive health checking) that directly explains
real production behavior. The specific WORDING of a reported symptom
("intermittent," "seems random") is itself diagnostic evidence -
intermittent failures with automatic failover in place point toward a
cycling/crash-looping root cause rather than a simple one-time failure.

### Key Distinction: 500 vs 502 (core lesson of this problem)
- 500 = the backend IS alive, received the request, but its own code
  threw an error it could still respond about (an error PAGE)
- 502 = Nginx got NO valid response from the backend at all - the
  backend is unreachable/crashed/hung (no page possible)
An unhandled exception inside a single route handler can only ever
produce a 500 in a properly running web server - achieving a real 502
requires the entire backend PROCESS to become unreachable, not just
one request's logic failing.

### Why This Matters Going Forward
Nginx's passive health checking (proven here AND in P09) is directly
relevant to Kubernetes' liveness/readiness probes (Module 06) and load
balancer health checks in cloud architecture (Module 05, 15, 21) -
this lab-proven mechanism is the same underlying concept, just at a
different layer of the stack.

### Key Takeaway
502 requires total backend unreachability, not just an application-
level error - and Nginx automatically and silently routes around dead
backends the moment it detects a failure, meaning a single dead
instance self-heals into invisible failures quickly, while genuinely
ongoing intermittent 502s point to a cycling/crash-loop pattern rather
than a simple, permanent outage.

## M04-P15 - Incident: DNS Not Resolving - Propagation vs Misconfiguration vs Caching

### The 3 Distinct Root Causes (precise mechanisms, not just "it takes time")

**Caching:** The authoritative source(s) of truth ALREADY have the
correct, updated answer. The problem is purely that a resolver or
device somewhere has an OLD, unrefreshed COPY it fetched before the
change, and its TTL hasn't expired yet (direct continuation of P02).

**Propagation:** The authoritative source(s) of truth THEMSELVES have
not finished syncing with each other yet. Most domains have MULTIPLE
authoritative DNS servers (redundancy) - when a record is updated, it
has to physically replicate across all of them, which takes real time.
During this window, even a completely FRESH query (zero caching
involved) can get different, genuinely inconsistent answers, purely
depending on WHICH specific authoritative server happens to be asked.

**Misconfiguration:** The record itself was entered wrong at the
source (typo, wrong record type, wrong target). EVERY authoritative
server, once synced, will consistently agree - just on the WRONG
answer. Unlike the other two, misconfiguration produces universal,
consistent failure, not a mix of correct/incorrect depending on who
asks.

Analogy used: 3 reception desks (NY/London/Tokyo) as authoritative
servers. Caching = a caller's own outdated sticky note. Propagation =
the desks themselves not yet having synced their information with
each other. Misconfiguration = ALL desks correctly agreeing on the
same, but wrong, information.

### Real Test That Initially Looked Like Propagation, But Wasn't
dig github.com @8.8.8.8 +short -> 20.207.73.82
dig github.com @1.1.1.1 +short -> 140.82.114.4

Different resolvers gave DIFFERENT real IPs for the SAME stable,
non-migrating domain. INITIAL WRONG INTERPRETATION: assumed this
looked like propagation disagreement. CORRECTED via investigation:
large-scale services like GitHub deliberately use DNS-level load
balancing / geographic routing, intentionally returning DIFFERENT
valid IPs to different queries at all times, with no migration or
inconsistency problem involved at all.

CRITICAL LESSON: seeing different IPs from different resolvers is NOT,
by itself, proof of a propagation problem - it could simply be normal,
intentional load-balancing behavior for a large service. Additional
context (a KNOWN recent DNS change, and a specific expected new value
missing from certain resolvers) is required to actually conclude
propagation delay, rather than jumping to that conclusion from
surface-level resemblance alone.

### The Decisive First Diagnostic Question
When a teammate reports "DNS isn't resolving to the new site for some
customers," the single most decisive first question is: "Is this
happening to ALL customers, or only SOME?"

- ALL customers, consistently affected -> MISCONFIGURATION (the record
  itself is wrong at the source; no amount of waiting or cache-
  clearing will fix it - the record itself must be corrected)
- SOME customers affected -> narrows to CACHING or PROPAGATION.
  Use `dig @specific-authoritative-server` (per-server, bypassing
  local resolvers entirely) to check whether different authoritative
  servers genuinely disagree with each other right now:
  - If authoritative servers themselves disagree -> PROPAGATION
    (still syncing; correct action is to wait, not to clear caches)
  - If all authoritative servers already agree (correctly) but some
    individual USERS still see the old site -> CACHING (correct
    action: wait for TTL to expire, or affected users can manually
    flush their own local DNS cache, per the P02 lesson)

### Why This Matters Going Forward
This decision tree turns a vague "DNS seems broken" complaint into a
single decisive first question, then a specific dig-based test -
avoiding wasted effort like telling users to "just wait" when the
actual problem is a misconfigured record that will NEVER self-resolve
no matter how long anyone waits. This is a strong, structured
interview answer for "how do you troubleshoot DNS issues after a
migration."

### Key Takeaway
Misconfiguration produces universal, consistent failure (fix the
record). Propagation produces genuine disagreement between different
authoritative servers on fresh queries (wait for sync). Caching
produces disagreement between individual users based on their own
stale local copies (wait for TTL, or manually flush). "Some customers
affected differently" does not, by itself, prove propagation - large
services often intentionally return different valid answers by
design (load balancing), and this must be distinguished using
targeted dig @server tests plus known context about the change,
not surface-level appearance alone.

## M04-P16 - Incident: Intermittent Connection Drops Under Load (File Descriptor Exhaustion)

### File Descriptors vs Inodes (distinction clarified this session)
Inode: permanent filesystem metadata for a file ON DISK - exists
independent of any running process.
File descriptor: a TEMPORARY, per-process reference to anything
currently open (a file, OR a network socket, OR a pipe) - network
connections consume file descriptors but have NO inode at all, since
they are not stored on disk. A process can exhaust its file descriptor
limit purely from network traffic, with zero relation to disk space or
inode availability - confirmed these are completely independent
failure categories.

### Checking Real Limits
ulimit -n (shell) -> 1024
cat /proc/<nginx-master-pid>/limits | grep "open files" ->
Max open files: 1024 (soft limit, currently enforced) / 524288 (hard
limit, the ceiling Nginx COULD be raised to, but isn't configured to
use)

### Real Incident: Client (ab) Hit Its Own Limit First
First load test attempt (ab -n 3000 -c 1500) failed immediately with
"socket: Too many open files (24)" - but this came from ab itself,
not Nginx. IMPORTANT LESSON: the load-testing TOOL needs enough of its
own file descriptor headroom to generate the intended load - if the
client runs out first, you are testing the client's limits, not the
server's. Fixed with `ulimit -n 4096` (comfortably above the 1500
concurrency target, not an arbitrarily huge number) before re-running.

### Real Test Results (genuine evidence, Nginx's real limit exceeded)
ab -n 3000 -c 1500 http://127.0.0.1/ (after raising ab's own limit):
Failed requests: 256, Non-2xx responses: 2872

Investigated the non-2xx responses directly rather than trust the
summary line alone - used -v 2 with grep/sort/uniq to get the real
breakdown: 2808 out of 2872 were specifically 502 Bad Gateway.

INITIAL WRONG GUESS: assumed these might be 429 Too Many Requests
(explicit rate limiting) - CORRECTED before even testing, since no
rate limiting (limit_req) has ever been configured anywhere in this
module's Nginx setup.

### Root Cause Mechanism (connects directly to P14)
Nginx needs roughly 2 file descriptors per CONCURRENT (simultaneous)
request: one for the incoming client connection, one for the outgoing
connection to the Flask backend. Confirmed via direct example: 15
simultaneous user requests require ~30 file descriptors (2 per
request), NOT per total requests served over time - concurrency is
what consumes file descriptors, not cumulative volume. A server
handling millions of requests sequentially, one at a time, would
barely use any file descriptors; a server handling many requests
AT ONCE is what drives exhaustion.

Under 1500 simultaneous connections in the real test, Nginx's own
1024 file descriptor limit was exceeded (needed ~3000, had 1024).

CRITICAL DISTINCTION from P14: the 502 mechanism is IDENTICAL (Nginx
cannot get a response from its backend) - but the ROOT CAUSE is
different:
- P14: the backend PROCESS itself was dead/crashed
- P16: the backend was healthy - NGINX ITSELF was resource-exhausted,
  unable to even open a new connection to reach a healthy backend

A wave of 502s does not automatically mean the backend crashed - it
can equally mean the load balancer/proxy itself has run out of
resources, requiring raising ulimits/tuning the proxy rather than
restarting the backend application.

### Why "It Went Away Once Traffic Dropped" Makes Sense
Key diagnostic detail distinguishing this from a P14-style crash loop.
A crashed backend would not self-resolve just from reduced traffic.
File descriptor exhaustion is purely a function of CONCURRENT load at
any given moment - fewer simultaneous connections means Nginx
immediately has free file descriptors again, with zero code changes
or restarts needed. How an incident self-resolves is real diagnostic
evidence of its root cause category.

### Real Fix (Production Context, Not Applied in This Lab)
Raise Nginx's soft limit toward its hard limit (524288) via systemd
service overrides (LimitNOFILE=) or worker_rlimit_nofile, matching
capacity to realistic peak concurrent load rather than the Ubuntu
default of 1024.

### Why This Matters Going Forward
Directly relevant to M04-P17 (Manager Task: reduce latency for
checkout API) and system design interviews about scaling load
balancers for peak traffic.

### Key Takeaway
File descriptors are consumed by CONCURRENT connections (roughly 2
per simultaneous request through a reverse proxy), not cumulative
request volume. A 502 can come from either a dead backend (P14) or a
resource-exhausted proxy unable to reach a healthy backend (P16) -
these require different fixes, and self-resolution as load decreases
is the signal distinguishing resource exhaustion from an application
crash.

## M04-P17 - Manager Task: Reduce Latency for Checkout API

### Measuring Latency Properly (Phase Breakdown)
curl -w with %{time_namelookup}, %{time_connect}, %{time_appconnect},
%{time_starttransfer}, %{time_total} breaks a request into distinct
phases (DNS, TCP connect, TLS handshake, time-to-first-byte, total) -
critical because each phase has a DIFFERENT root cause and fix. A
single "total time" number cannot distinguish network latency from
application processing time.

### Real Incident: Loopback Testing Is Meaningless for Customer Latency
First baseline test used http://127.0.0.1 FROM the EC2 itself - all
phases under 2ms. CORRECTED: this tells us NOTHING about real customer
experience, since it never touches the actual internet (no real
network distance, no real DNS resolution). Re-tested from an actual
external laptop against the public IP instead - the only test that
genuinely represents what a customer experiences.

### Real External Measurement
curl -w test from external laptop to public IP:
DNS Lookup: 0.000421s | TCP Connect: 0.077673s | TLS Handshake: 0s |
Time to First Byte: 0.133734s | Total: 0.133946s

Breakdown: ~78ms was real network/geographic distance (mostly outside
direct control - physics + routing). ~56ms (134ms total - 78ms
connect) was spent AFTER connection established, before any response
data arrived - this is actual Nginx+Flask PROCESSING time, and the
genuinely actionable part of this task.

### Root Cause Identified: Flask's Development Server
~56ms processing time for a route that just returns a hardcoded
string is notably slow for such trivial work. Root cause: Flask's
built-in dev server (Werkzeug) is explicitly NOT designed for
production performance (per its own startup warning, first seen in
P06) - it is single-threaded by default, meaning concurrent requests
QUEUE and wait for the previous one to finish, even if the actual work
each request does is trivially fast. This affects LATENCY specifically
(not just capacity) - a request's own work might be instant, but time
spent waiting in queue behind other requests still counts as latency
from the customer's perspective.

### Real Incident: sys.argv Conflicts With Gunicorn's Own Arguments
First attempt to run app.py under Gunicorn (gunicorn --workers 3
--bind 127.0.0.1:5020 app:app) crashed immediately: ValueError:
invalid literal for int() with base 10: '--workers'. Root cause:
app.py's `port = int(sys.argv[1])` pattern assumed direct script
execution (python3 app.py 5001) - but Gunicorn loads the app as an
imported WSGI module, and sys.argv reflected GUNICORN's own CLI flags
instead, not a port number. Real lesson: code written for one
execution method (direct script + custom CLI args) is not
automatically compatible with a different execution method (imported
by a WSGI server) - this is exactly why production apps typically read
config from environment variables, not sys.argv.

FIXED by adding `.isdigit()` validation before attempting int()
conversion, falling back to os.environ.get('PORT', 5000) otherwise:
port = int(sys.argv[1]) if len(sys.argv) > 1 and
sys.argv[1].isdigit() else int(os.environ.get('PORT', 5000))
Confirmed the exact mechanism: '--workers'.isdigit() returns False
(contains non-digit characters), so execution safely falls through to
the environment-variable default instead of crashing.

### Real Incident: ab Hung Indefinitely Against a Dead Port
A load-test comparison attempt against port 5001 returned completely
blank output and had to be manually interrupted (Ctrl+C). Investigated
via ss -tuln + ps aux rather than retry blindly - confirmed NOTHING
was listening on port 5001 at all (a leftover from earlier module
testing). Noteworthy edge case: ab appears to HANG rather than fail
fast when the target port has no listener, unlike curl's typical
instant "connection refused" - worth remembering when a load test
seems to stall with zero output. Fixed by restarting the dev server
instance properly before re-running the comparison.

### Real, Measured Comparison (the actual deliverable for this task)
Identical load test (ab -n 300 -c 50) against both servers:

| Server                          | Mean Time Per Request |
|----------------------------------|------------------------|
| Flask dev server (single-thread) | 41.544 ms              |
| Gunicorn (3 workers)             | 15.708 ms              |

RESULT: ~62% reduction in mean request latency under identical
concurrent load (50 simultaneous connections), achieved purely by
switching the WSGI server - ZERO application code logic was changed.
Zero failed requests on either server at this load level (contrast
with P16, where much higher concurrency, 1500, caused genuine
failures even on the dev server due to file descriptor exhaustion -
this test uses a moderate, realistic load specifically to isolate the
WSGI server difference, not to reproduce total exhaustion).

### Recommendation (Manager-Ready Summary)
"Checkout API latency was measured end-to-end from an external client,
not just locally. External network transit accounts for ~78ms
(largely fixed, tied to customer geographic distance). The remaining,
actionable ~56ms of processing time is explained by Flask's
development server being single-threaded, which serializes concurrent
requests. Switching to Gunicorn with multiple worker processes reduced
mean request latency by ~62% under identical concurrent load in direct
testing (41.5ms to 15.7ms), with zero changes to application logic.
Recommend deploying Gunicorn (or an equivalent production WSGI server)
behind Nginx for the checkout API specifically, as the single
highest-impact, lowest-risk change available."

### Why This Matters Going Forward
This exact dev-server-vs-production-WSGI-server distinction, and the
external-vs-local measurement discipline, are both standard real
interview topics for "how would you diagnose and fix API latency."
The phase-breakdown curl technique is directly reusable for any future
latency investigation in this workbook or on the job.

### Key Takeaway
Never measure latency from localhost - it excludes the real network
path entirely. Break latency into phases (DNS/connect/TLS/processing)
to target the actual bottleneck instead of guessing. Flask's dev
server is single-threaded and unsuitable for any real latency-
sensitive production traffic; a real WSGI server with multiple workers
directly reduces queuing-induced latency, provable with real, run
side-by-side measurements rather than assumed.

## M04-P17 Addendum - Verifying the Fix With a Genuine External Test

### Real Incident: Multiple False "External" Tests Were Actually Internal
After deploying Gunicorn to port 5001 (replacing that backend's dev
server), attempted to re-verify with an external latency test. THREE
consecutive attempts produced suspiciously fast results (near-zero,
sub-millisecond TCP connect times) that were WRONGLY assumed to be
genuine improvements at first glance. Investigated rather than
accepted implausible good news: ran whoami/hostname in the SAME
window used for testing - confirmed all three "external" tests were
actually run from INSIDE the EC2's own SSH session (whoami: ubuntu,
hostname: ip-172-31-13-66), not from the laptop at all. This
reproduced the exact same class of mistake as the original P17
loopback test, just disguised differently (testing the public IP FROM
the EC2 itself, rather than 127.0.0.1, produces similarly
unrepresentative fast results via AWS's internal routing).

Fixed by explicitly opening a genuinely separate, local terminal (Git
Bash on the actual Windows laptop) and re-verifying its identity
(whoami/hostname showing the real laptop, not the EC2) BEFORE trusting
any timing result from it.

### Real Incident: Another EC2 Reboot Mid-Verification
While verifying, a 502 Bad Gateway appeared unexpectedly. Investigated
via ss -tuln + ps aux (standard method by now) - confirmed ALL 3
backends were dead again. uptime showed "up 11 min" - a THIRD EC2
reboot during this single session, also explaining the public IP
change noticed earlier (13.233.117.30 -> 13.201.78.186). This is now
a clearly RECURRING environmental instability (reboots have now
disrupted P12 and P17 in this same session) - worth flagging as a
standing operational reality of this Free Tier lab environment:
ALWAYS verify backend processes are alive (ss -tuln) before trusting
any measurement, especially after any gap in activity, rather than
assuming a previous setup is still intact.

### Final, Verified External Measurement
Confirmed via curl -s (checked response body for "port 5001" BEFORE
trusting the timing test) that the request genuinely hit the
Gunicorn-upgraded backend:

BEFORE (dev server): Total 133.9ms (Connect: 77.7ms, Processing: ~56ms)
AFTER (Gunicorn, confirmed hit): Total 52.6ms (Connect: 25.5ms,
Processing: ~27ms)

Processing time specifically: ~56ms -> ~27ms, ~52% reduction -
genuinely consistent with the independently-measured ~62% reduction
from the local ab load test, corroborating the finding via two
different methods (controlled local load test AND real external
single-request measurement).

### Key Lesson Reinforced
An implausibly GOOD result deserves the same scrutiny as an
implausibly BAD one - the instinct to investigate should not be
reserved only for failures or errors. Verifying the actual vantage
point (whoami/hostname) and the actual backend that answered (reading
the response body, not just the timing numbers) were both necessary
to trust this measurement as genuine evidence rather than an artifact
of testing from the wrong place.

## M04-P18 - Manager Task: Set Up HTTPS Before Friday's Launch

### The Real Constraint: A Domain Is Required, Not Just an IP
Let's Encrypt (the free, automated CA referenced in P10) CANNOT issue
certificates for raw IP addresses - its automated domain-ownership
verification process is built entirely around proving control of a
real domain name (via DNS or served files), which an IP address alone
cannot satisfy. This is a genuine, real prerequisite to flag to a
manager before Friday - a domain must be registered and pointed at the
server first; this cannot be skipped or worked around technically.

### Lab Workaround: nip.io (Verified Real, Not Just Assumed)
For lab/testing purposes without registering a real domain, used
nip.io - a free service providing wildcard DNS that automatically
resolves <any-ip>.nip.io to that exact IP. Verified directly:
dig 13.201.78.186.nip.io +short returned 13.201.78.186 - confirmed
genuinely working before relying on it. Explicitly NOT suitable for a
real production launch (reveals the IP directly, breaks the moment
the IP changes) - purely a legitimate way to prove the Certbot/Let's
Encrypt process works technically, in a lab without a real domain.

### Certbot - Real Installation and Real Incident
sudo apt install certbot python3-certbot-nginx -y
Installation automatically created a systemd TIMER
(certbot.timer) - since real Let's Encrypt certificates expire every
90 days, this handles automatic renewal in the background, addressing
a real, common production incident category (expired-cert outages)
before it can happen.

REAL INCIDENT: sudo certbot --nginx -d 13.201.78.186.nip.io
successfully ISSUED the certificate (Let's Encrypt genuinely verified
domain ownership), but FAILED to automatically install/deploy it into
Nginx: "Could not automatically find a matching server block... Set
the server_name directive."

ROOT CAUSE: existing Nginx config used `server_name _;` (P06/P10's
generic wildcard, matching any hostname) rather than the actual
domain name. Certbot's Nginx plugin requires a server_name that
LITERALLY matches the requested domain to know which block to edit -
a generic wildcard doesn't satisfy this, since it doesn't "name" any
specific domain to match against.

FIXED by updating server_name to the real domain
(13.201.78.186.nip.io) in both HTTP and HTTPS server blocks, then
re-running the install step specifically:
sudo certbot install --cert-name 13.201.78.186.nip.io
-> "Successfully deployed certificate"

### What Certbot Actually Changed (verified via cat, not assumed)
1. ssl_certificate / ssl_certificate_key paths updated from the old
   self-signed files (/etc/nginx/ssl/selfsigned.*, from P10) to the
   new real certificate: /etc/letsencrypt/live/<domain>/fullchain.pem
   and privkey.pem
2. Automatically ADDED an HTTP-to-HTTPS redirect block:
   if ($host = <domain>) { return 301 https://$host$request_uri; }
   RECOGNIZED as the same correct redirect LOGIC already validated as
   correct back in P11's debug challenge - Certbot automates a best
   practice already understood conceptually, just scoped with an
   explicit host-match condition rather than being unconditional.

### Real, Verified End-to-End Proof (from actual external laptop)
curl -v https://13.201.78.186.nip.io/ - succeeded with a clean 200 OK,
WITHOUT the -k flag required back in P10 for the self-signed cert -
direct, definitive proof the certificate is genuinely trusted by
default, matching exactly what a real customer's browser would
experience (no warnings, padlock-verified).

curl -v http://13.201.78.186.nip.io/ - confirmed 301 Moved Permanently
with Location: https://13.201.78.186.nip.io/ - HTTP-to-HTTPS redirect
genuinely working.

### Why This Matters Going Forward
The domain-ownership prerequisite is a common real-world blocker
non-technical stakeholders don't anticipate - flagging it clearly and
early (rather than after Friday) is itself a valuable, demonstrable
professional skill. The self-signed-vs-CA-signed distinction from P10
is now fully closed with a real, working, verified CA-signed
deployment - directly reusable knowledge for any future real project
requiring public HTTPS.

### Key Takeaway
Let's Encrypt requires a real, verifiable domain - never a bare IP -
and this constraint must be surfaced to stakeholders as a real
planning dependency, not discovered at the last minute. Certbot's
Nginx plugin requires server_name to literally match the target
domain to auto-edit the right config block; a generic wildcard
(server_name _;) breaks this automation, even though it works fine
for ordinary traffic routing. The presence (or absence) of the -k
flag being required is itself a simple, direct way to verify whether
a certificate is genuinely CA-trusted versus self-signed.

## Quick Reference: Steps to Add Real HTTPS (Let's Encrypt) to Nginx

1. Prerequisite: you need a real domain name pointing at your server's
   IP (Let's Encrypt cannot issue certs for bare IP addresses). For
   lab/testing without a real domain, <your-ip>.nip.io works as a free
   wildcard DNS workaround (verify with `dig <ip>.nip.io +short`).

2. Install Certbot with the Nginx plugin:
   sudo apt install certbot python3-certbot-nginx -y

3. IMPORTANT: before running Certbot, make sure your Nginx config's
   server_name directive is set to the ACTUAL domain, not a generic
   wildcard (server_name _;). Certbot's Nginx plugin needs an exact
   match to know which server block to edit.
   sudo nano /etc/nginx/sites-available/<your-config>
   -> change server_name _; to server_name yourdomain.com; (in both
      the port 80 and port 443 blocks)
   sudo nginx -t
   sudo systemctl reload nginx

4. Run Certbot, pointing it at your domain:
   sudo certbot --nginx -d yourdomain.com
   - Enter an email address (for renewal/expiry notices)
   - Agree to the terms of service
   This both ISSUES the certificate AND attempts to auto-install it
   into Nginx in one step.

5. If step 4's auto-install fails (commonly due to step 3 being
   skipped), the certificate is still issued and saved - just install
   it separately once server_name is fixed:
   sudo certbot install --cert-name yourdomain.com

6. Verify what Certbot changed:
   cat /etc/nginx/sites-available/<your-config>
   Expect: ssl_certificate and ssl_certificate_key now point to
   /etc/letsencrypt/live/yourdomain.com/fullchain.pem and privkey.pem
   (replacing any old self-signed paths), plus an automatically added
   HTTP-to-HTTPS redirect block.

7. Verify real, trusted HTTPS from an external client (not the server
   itself, not via loopback):
   curl -v https://yourdomain.com/
   Success looks like: a clean 200 OK with NO -k/--insecure flag
   needed - this is the definitive proof the certificate is genuinely
   CA-trusted (contrast with a self-signed cert, which requires -k or
   throws a verification error).

8. Verify the HTTP-to-HTTPS redirect works:
   curl -v http://yourdomain.com/
   Success looks like: 301 Moved Permanently with a Location header
   pointing to the https:// version.

9. Automatic renewal: Certbot's installation creates a systemd timer
   (certbot.timer) automatically - no manual cron job needed. Real
   Let's Encrypt certs expire every 90 days; this timer handles
   renewal in the background before that happens.

## M04-P19 - Architecture: 3-Tier Network Design

### Why Separate Tiers At All - Blast Radius
Core reasoning: if an attacker compromises ONE tier, network-level
separation (not just application logic) limits what they can reach
next - this is defense-in-depth (P07's principle: Flask bound to
127.0.0.1 behind Nginx) applied at architectural scale instead of a
single server. Compromising the web tier should NOT automatically
expose the database - the network itself, not just app permissions,
must enforce this boundary.

### Public vs Private Subnets
- Public subnet: has a direct route to the internet (via an Internet
  Gateway). ONLY the web tier belongs here - it is the sole tier that
  genuinely needs to be internet-reachable.
- Private subnet: NO direct route to the internet, in either
  direction, by default. App tier and database tier both belong here
  - unreachable directly from the internet; only reachable THROUGH
  the web tier, exactly like Flask/127.0.0.1 in P06, enforced at the
  network layer this time instead of just app binding.

### NAT Gateway - Solving Outbound-Only Access for Private Resources
Problem: private-subnet resources (app tier) sometimes genuinely need
OUTBOUND internet access (patches, external APIs, package downloads)
but must NEVER be reachable via unsolicited INBOUND connections.

Mechanism: a NAT Gateway sits in the PUBLIC subnet (has its own real
internet access) and relays outbound requests on behalf of private
resources - similar in spirit to how Nginx relayed requests to Flask
in P06, just for the reverse direction (outbound instead of inbound).
From the internet's perspective, outbound traffic appears to originate
from the NAT Gateway's own public IP.

CRITICAL one-directional guarantee: because the PRIVATE resource
always initiates the conversation (acting as the client, using an
ephemeral port, per the P01 model), and the NAT Gateway only relays
responses to ALREADY-INITIATED conversations, there is no mechanism
for a brand-new, unsolicited inbound connection to ever reach the
private resource. An attacker sending a fresh request directly at the
NAT Gateway's public IP has NO matching outbound conversation to route
against - it is structurally dropped, not just blocked by a
configurable rule that could be misconfigured.

Cost note (from STATUS.md's own resource-hygiene flag): NAT Gateways
bill per-hour AND per-GB processed - a real, easy-to-overlook ongoing
cost, worth deliberately scoping to only the private resources that
genuinely need outbound access.

### Mapping Our Own Lab Onto the 3-Tier Model
- Web tier -> Nginx (public subnet, public IP, receives all customer
  traffic, the only internet-facing component)
- App tier -> Flask (private subnet, no direct internet exposure,
  only reachable via Nginx's proxy_pass - our whole module's actual
  setup has been running these on ONE EC2, a deliberate lab
  simplification of what would be two separate subnets/instances in
  real production)
- Data tier -> a real database (never actually built in this lab,
  Flask only returns hardcoded strings) - would live in a private
  subnet, with Security Group rules restricting inbound access
  SPECIFICALLY to the app tier's Security Group, not the entire
  private CIDR range broadly. Common stronger real-world practice:
  a SEPARATE private subnet specifically for the database, distinct
  from the app tier's private subnet, as an additional independent
  blast-radius boundary.

### Security Group Principle Applied at Architecture Scale
Same specific-allow-list discipline as P07's ufw lesson (allow only
what is explicitly needed, never broadly) - applied here to Security
Groups between tiers: the database's Security Group should allow
inbound traffic ONLY from the app tier's specific Security Group
(referenced by SG ID, not a broad CIDR range), never "anything in the
private subnet" generically.

### Why This Matters Going Forward
This 3-tier + NAT Gateway model is standard architecture vocabulary
for AWS solutions architect and DevOps interviews (directly relevant
to M04-P21 System Design and Module 05/15 AWS/EKS modules) - the
blast-radius reasoning and outbound-only NAT mechanism are both
common, specific interview questions ("how would you design network
isolation for a 3-tier app").

### Key Takeaway
3-tier network separation limits blast radius at the network level,
not just application logic. Only the web tier needs a public subnet;
app and data tiers stay private. A NAT Gateway provides outbound-only
internet access for private resources via a structural (not just
configured) one-directional guarantee - based on the client always
initiating the connection first, exactly as ephemeral ports work in
the P01 model. Security Groups between tiers should reference specific
source Security Groups, not broad CIDR ranges, mirroring the
allow-list discipline from ufw in P07.

## M04-P20 - Architecture: Nginx vs HAProxy vs ALB Tradeoffs

### Origin and Primary Purpose
- Nginx: originally a WEB SERVER (static file serving) that later
  gained reverse-proxy/load-balancing features - does double duty as
  both a full web server AND a proxy (exactly how it was used all
  module: static-style responses, TLS termination P10, load balancing
  P09, all in one tool)
- HAProxy: purpose-built from the ground up for ONE job only -
  load balancing/proxying, no web-serving features at all. Often
  cited as having more advanced/precise load-balancing algorithms and
  health-check tuning than Nginx's defaults, specifically because it
  has no other responsibilities competing for its design focus
- ALB (Application Load Balancer): not installed/configured software
  at all - a FULLY MANAGED AWS service

### Self-Managed (Nginx/HAProxy) vs Managed (ALB) - The Real Tradeoff
Self-managed: FULL control (custom config logic, any module, any
parameter tuning) but FULL responsibility - patching security
vulnerabilities, scaling manually as traffic grows, ensuring survival
across reboots, monitoring health. Directly experienced this cost
firsthand across this session: THREE separate real EC2 reboots (P12,
P17-addendum) each required manually restarting Flask/Gunicorn
processes - nohup alone does not even survive a reboot (only a
session ending), only a real supervisor (systemd, which Nginx itself
uses) does.

Managed (ALB): AWS handles scaling, patching, and availability
AUTOMATICALLY and invisibly - confirmed via direct reasoning that an
ALB would NEVER have required the kind of manual intervention
personally experienced this session (checking uptime, restarting dead
processes, diagnosing ss -tuln after each reboot). Tradeoff: limited
to whatever configuration ALB exposes through its own interface - no
custom modules, no arbitrary config logic the way Nginx/HAProxy allow.

### When to Choose Which (synthesized from the tradeoffs)
- Nginx: when you want ONE tool for multiple jobs (web serving +
  proxying + TLS termination + caching), and value configuration
  flexibility
- HAProxy: when load balancing/proxying performance and fine-grained
  control is the SOLE priority, with no need for general web-server
  features
- ALB: when minimizing operational overhead matters more than
  configuration flexibility - a classic "build vs buy" tradeoff;
  commodity infrastructure work (basic load balancing) is often better
  left to a managed service, reserving self-hosted tools for genuinely
  custom logic a managed service cannot provide

### Why This Matters Going Forward
This exact self-managed vs managed tradeoff reasoning generalizes far
beyond load balancers - directly relevant to Module 05 (AWS services
generally), Module 15 (EKS vs self-managed Kubernetes), and Module 21
(System Design) interview questions about infrastructure choices. The
personal, lived evidence of manual reboot recovery this session is a
genuinely strong, concrete example to cite in an interview when asked
"why would you choose a managed service."

### Key Takeaway
Nginx and HAProxy trade operational responsibility for configuration
flexibility; ALB trades configuration flexibility for zero operational
burden. The choice is not about which is objectively "better" but
about which tradeoff fits the situation - custom, complex routing
logic favors self-hosted; commodity, standard load balancing favors
managed, especially when the team's real, lived operational cost of
self-hosting (as personally experienced this session) outweighs the
value of the extra control.

## M04-P21 - Unguided RCA: Reproduce and Root-Cause a Connectivity Failure

### RCA Report

**Problem:** Reported symptom: "tried hitting the site, got a 502."
Investigation revealed this was actually TWO separate, independent
problems layered on top of each other - not one single root cause.

**Impact:** Complete inability to reach the site both locally (502)
and externally (timeout), for reasons that turned out to be entirely
unrelated to each other.

**Timeline (self-directed investigation, no guided hints):**
1. dig 13.201.78.186.nip.io +short - confirmed DNS resolved correctly
   and instantly, ruling out DNS as a factor
2. curl -I http://13.201.78.186.nip.io - hung indefinitely with zero
   output, requiring manual interruption
3. nc -vz -w 5 13.201.78.186 80 - confirmed a genuine TIMEOUT (not
   refused) from an external-style test
4. sudo ss -lntp | grep ':80' - confirmed Nginx was alive and
   listening on 0.0.0.0:80
5. sudo ufw status verbose - confirmed port 80 explicitly allowed
6. curl -v http://127.0.0.1 (loopback, local) - unexpectedly
   SUCCEEDED in reaching Nginx, but returned a real 502 Bad Gateway -
   this was the key moment that revealed TWO separate problems
   existed: a working local connection with a bad response (502),
   and a completely blocked external connection (timeout) - these
   could not share one single root cause, since a 502 requires Nginx
   to have successfully processed a request, while the external test
   never got that far at all
7. Investigated the 502 first: ss -tuln | grep -E "5001|5002|5003"
   returned BLANK - no backend processes listening at all
8. uptime showed "up 51 min" - confirmed the EC2 instance had
   rebooted, killing all nohup-backed Flask/Gunicorn processes (same
   root cause pattern as P12 and the P17 addendum - nohup survives a
   session ending but NOT a full machine reboot)
9. Restarted all 3 backend processes (Flask on 5002/5003, Gunicorn on
   5001) - confirmed via ss -tuln and curl that the 502 was resolved
10. Re-tested nc against the original IP - STILL timed out, confirming
    this was a genuinely separate, still-unresolved second issue
11. Re-verified every remaining layer of the 3-gate model (Security
    Group inbound rules, checked directly in the AWS console) - found
    all three expected rules present and correctly configured (SSH/22,
    HTTPS/443, HTTP/80, all source 0.0.0.0/0)
12. With every layer of the model checked and appearing correct, and
    knowing a reboot had JUST occurred, checked the EC2 instance's
    CURRENT public IP directly in the console - found it had changed
    from 13.201.78.186 to 3.110.222.249, exactly matching the
    documented "public IP changes on stop/start" behavior in
    STATUS.md
13. Re-tested nc against the NEW, correct IP - succeeded immediately,
    confirming this as the actual root cause of the second problem

**Root Cause:**
- Problem 1 (502): the EC2 instance rebooted, and all nohup-backed
  Flask/Gunicorn backend processes died with it (nohup does not
  survive a full reboot, only a session ending) - Nginx itself
  survived automatically (systemd-managed), but had nothing to
  actually forward requests to.
- Problem 2 (external timeout): the SAME reboot also changed the
  EC2's public IP address. All external connectivity tests were being
  run against the OLD, now-invalid IP - every layer being tested
  (Security Group, ufw, Nginx binding) was actually configured
  correctly the entire time; the target address itself was simply
  wrong.

**Resolution:**
1. Manually restarted all 3 backend processes via nohup
2. Identified and switched to the instance's new, current public IP
   for all further testing

**Preventive Action:** For problem 1 - use a real process supervisor
(systemd service, or Docker/Kubernetes in later modules) instead of
nohup, so backend processes survive reboots automatically, not just
session endings. For problem 2 - this is exactly the real-world
justification for an AWS Elastic IP (a static, unchanging public IP),
first identified as a gap back in P08 - would have entirely prevented
wasting investigation time on a target address that was silently
stale.

**Lessons Learned:**
1. A single reported symptom ("got a 502") does not guarantee a
   single root cause - two genuinely independent problems can coexist
   and must be recognized as separate once evidence stops fitting one
   unified explanation (the moment loopback curl SUCCEEDED while
   external nc still TIMED OUT was the critical signal that split
   this into two investigations).
2. When every layer of a well-established diagnostic model (3-gate:
   Security Group, ufw, application) checks out as correct, but the
   symptom persists, the problem may not be IN the model at all - it
   may be a stale assumption about the target itself (in this case,
   an IP address that had silently changed). Re-verifying the most
   basic assumption (is this even the right address anymore) after
   exhausting the standard checklist was what actually found the real
   cause.
3. A known environmental instability (EC2 reboots causing both
   process loss AND IP changes, both already documented earlier this
   session in P12/P17) can resurface and cause MULTIPLE simultaneous,
   seemingly unrelated symptoms from a SINGLE underlying event - worth
   checking `uptime` early in any future unexplained connectivity
   investigation in this specific lab environment.

### Why This Matters Going Forward
This is a realistic simulation of a genuinely common senior-level
debugging challenge: distinguishing "one root cause, multiple
symptoms" from "coincidentally simultaneous, unrelated root causes" -
directly relevant to real production incidents and a strong
interview narrative for "describe a time you debugged something
complex."

### Key Takeaway
Evidence that doesn't fit a single explanation is a signal to split
the investigation into separate hypotheses, not to keep forcing one
theory to explain everything. When an entire diagnostic model checks
out clean but the symptom remains, re-verify the most basic
assumptions about the target itself before assuming the model missed
something.

## M04-P22 - Standalone Interview Q&A Round (Full Answers)

Rapid-fire, no-notes interview simulation covering the full module.
Score: 8/10 solid on first attempt, 2 needed clarification.

### Q1: Difference between TCP and UDP, and a real-world use case for each
TCP is connection-oriented - it performs a 3-way handshake (SYN,
SYN-ACK, ACK) before any data flows, guarantees delivery (re-sends
lost packets), and guarantees order (reassembles out-of-order packets
correctly). UDP is connectionless - no handshake, no delivery
guarantee, no re-sending of lost data; it fires data and moves on.
Use cases: HTTP/web traffic and chat messages use TCP, since a lost
or out-of-order chat message must never silently vanish. Live video
calls and DNS lookups use UDP, since a dropped video frame or a lost
DNS query (which can simply be retried) is preferable to the latency
cost of TCP's handshake and retransmission overhead.
ANSWERED CORRECTLY.

### Q2: A user reports "connection refused." What does this tell you, and what does it rule out?
"Refused" means the request GENUINELY REACHED the destination
machine's operating system, and something there actively rejected it
- either nothing is listening on that port/interface, or the
application explicitly declined the connection. This is a FAST,
active response. It RULES OUT a Security Group or firewall block
earlier in the network path, because a block at that layer would
silently drop the packet with zero response, producing a TIMEOUT
(slow, no reply at all) instead of a refusal. Refused = something
answered "no"; timeout = nobody answered at all.
INITIALLY ANSWERED INCOMPLETELY - clarified above.

### Q3: What is the actual purpose of a certificate's private key versus its public certificate in a TLS handshake?
The PRIVATE KEY stays exclusively on the server and is used to prove
the server's identity and decrypt data that was encrypted using the
matching public key - specifically, it lets the server safely receive
a symmetric key the client encrypted using the public key, since only
the private key can decrypt that exchange. The PUBLIC CERTIFICATE is
freely distributed to any client that connects; it contains the
public key plus identifying information (domain name, issuing CA),
and the client uses it to verify the server's identity and encrypt
the initial key-exchange data. Together, they let the two sides
safely agree on a shared symmetric key without ever transmitting that
secret in a form an eavesdropper could use.
(Compromise consequence, for context: if the private key were ever
stolen, an attacker could impersonate the server to any client - but
that is a CONSEQUENCE of the key's purpose, not the purpose itself.)
INITIALLY ANSWERED WITH THE COMPROMISE SCENARIO INSTEAD OF THE
PURPOSE - clarified above.

### Q4: Difference between a reverse proxy and a load balancer. Can one tool be both?
A reverse proxy sits in front of a backend and forwards client
requests to it on the client's behalf, hiding the backend's real
address/existence from the outside world (e.g. Nginx forwarding to
Flask on 127.0.0.1, invisible to the internet). A load balancer
specifically distributes incoming traffic across MULTIPLE backend
instances, using an algorithm (round-robin, least-connections, ip-hash)
to decide which one handles each request. Yes, one tool can genuinely
be both simultaneously - Nginx (and HAProxy) commonly serve as a
reverse proxy AND a load balancer at the same time, exactly as
configured in this module (P06's single-backend reverse proxy became
P09's multi-backend load-balancing upstream block, same tool, same
config style, just pointed at more than one server).
ANSWERED CORRECTLY.

### Q5: Why does a load balancer using ip_hash risk uneven traffic distribution compared to round-robin?
Round-robin distributes requests strictly in sequence regardless of
who is sending them, guaranteeing an even spread of REQUEST COUNT
across backends over time. ip_hash instead maps a given client IP
consistently to the SAME backend every time (for session-consistency
reasons - e.g. an in-memory shopping cart tied to one specific
server). If certain IPs generate disproportionately more traffic than
others (e.g. one very active user, or many users behind the same
corporate NAT sharing one visible IP), all of that traffic gets
funneled to whichever single backend that IP happens to hash to,
while other backends may sit comparatively idle - trading even
distribution for session stickiness.
ANSWERED CORRECTLY.

### Q6: Exact difference between a 500 and a 502 status code
500 Internal Server Error means the backend application ITSELF IS
ALIVE, received the request, and its own code threw an unhandled
exception or error while processing it - the backend still manages to
generate and send back a real (if unhelpful) response describing the
failure. 502 Bad Gateway means the PROXY (e.g. Nginx) could not get
ANY valid response from its backend at all - the backend is
unreachable, crashed entirely, or hung with no response whatsoever,
so the proxy itself generates the 502 on the backend's behalf, since
the backend never had the chance to respond. In short: 500 = "I'm
alive but broke while handling this"; 502 = "I asked my backend and
got total silence/failure."
INITIALLY JUST NAMED BOTH WITHOUT EXPLAINING THE MECHANISM -
clarified above.

### Q7: Actual purpose of an ephemeral port, and does the server or client use one?
An ephemeral port is a TEMPORARY, randomly-assigned port number that
the CLIENT side of a connection uses for that one specific outgoing
connection - a fresh one is assigned for every new connection, even
to the identical destination. This exists because a single client
machine's IP address stays fixed, but it may have many simultaneous
connections open at once (multiple browser tabs to the same site, for
example) - the ephemeral port is what lets the operating system tell
these otherwise-identical connections apart, since the full
connection identity is (client IP, client ephemeral port, server IP,
server FIXED port). The SERVER, by contrast, always listens on one
fixed, known port (e.g. 443) so that clients can reliably find it -
the server never uses an ephemeral port for its own listening socket.
INITIALLY DESCRIBED THE EFFECT (enabling multiple tabs) RATHER THAN
THE DEFINITION ITSELF - clarified above.

### Q8: Difference between propagation delay and DNS caching, and how to distinguish using dig
DNS caching is the actual mechanism: different resolvers/clients hold
onto an old, previously-fetched DNS answer until its TTL expires, even
though the authoritative source already has the correct, updated
answer. "Propagation delay" is really just the informal, observed
NAME for the time it takes those various cached copies, scattered
across many different resolvers worldwide, to naturally expire and
get refreshed - it is not a fundamentally separate mechanism, just the
aggregate, real-world EFFECT of caching's built-in delay playing out
across the internet's many independent resolvers. To distinguish
"is this actually propagating/still cached somewhere" from "is the
record itself simply wrong," use dig @<specific-authoritative-server>
+short to query an authoritative source DIRECTLY, bypassing all local
and intermediate caches - if the authoritative answer is already
correct, any lingering wrong answers seen elsewhere are just
caching/propagation catching up; if the authoritative answer itself
is wrong, that points to a genuine misconfiguration instead.
ANSWERED CORRECTLY AND PRECISELY - stronger than typical, reflecting
the corrected understanding built during P15's own investigation.

### Q9: A wave of 502s appears during a traffic spike, then disappears once traffic drops. Likely cause, and how does it differ from a crash-loop causing intermittent 502s?
Likely cause: FILE DESCRIPTOR EXHAUSTION on the proxy (Nginx) itself -
under high concurrent load, Nginx needs roughly 2 file descriptors per
simultaneous request (one for the incoming client connection, one for
the outgoing connection to the backend), and can exceed its configured
limit (e.g. 1024) purely from CONCURRENCY, even with a perfectly
healthy backend. This SELF-RESOLVES automatically once concurrent load
decreases, since file descriptors free up immediately with no code
changes or restarts needed. This is fundamentally different from a
CRASH LOOP (a backend repeatedly crashing and restarting), which would
NOT be fixed just by reduced traffic - a crash-looping backend keeps
crashing regardless of how much or how little load it receives, so its
502s would persist independent of traffic volume, whereas file
descriptor exhaustion is directly, deterministically tied to
concurrent load level at any given moment.
ANSWERED CORRECTLY.

### Q10: Why put a database in a private subnet with no direct internet route, but still need a NAT Gateway somewhere in the architecture? What is the NAT Gateway actually for, if the database itself needs no outbound internet access either?
The database sits in a private subnet specifically so it is NEVER
directly reachable from the internet, limiting blast radius if the
web tier is ever compromised - and a database typically has NO
legitimate reason to initiate outbound internet connections either,
so it needs neither inbound nor outbound direct internet access. The
NAT Gateway instead exists to serve the APP TIER's occasional,
legitimate OUTBOUND-only needs - such as downloading security patches,
calling external APIs (payment processors, email services), or
pulling packages/images from public registries - while still keeping
the app tier itself fully unreachable via any unsolicited INBOUND
connection from the internet. The NAT Gateway's one-directional
guarantee (only relays responses to connections the private resource
itself already initiated) is what makes this outbound-only access
possible without compromising the tier's inbound isolation.
ANSWERED CORRECTLY.

### Key Retention Gaps Identified
Two of the "needs clarification" answers shared a pattern: describing
an EFFECT or CONSEQUENCE of a concept rather than its actual
DEFINITION or MECHANISM (Q3: compromise risk instead of purpose; Q7:
symptom of use instead of definition; similarly Q6 initially just
named terms rather than explaining mechanism). Worth deliberately
practicing stating definitions precisely and leading with mechanism,
not just recognizing what a concept is used for or what breaks
without it - a common, correctable gap under real interview pressure.

### Why This Matters Going Forward
This rapid-fire format closely simulates Round 2 (DevOps tools +
hands-on scenarios) of the Adobe-style interview structure referenced
in the master prompt - worth repeating this exact Q&A style as a
warm-up before Module 25's formal mock interviews, and worth
re-reading these full answers as spaced-repetition material before
any real interview.

## M04-P23 - Timed Interview Challenge: 3 Rapid Networking Scenarios

### Scenario 1: Sudden total timeout, no deployment
Correct approach: timeout (not refused) + zero code deployment
strongly points to Gate 1 (Security Group) - specifically check for a
recently removed/restricted inbound rule. REAL MISTAKE MADE UNDER TIME
PRESSURE: initially proposed checking "if port 443 is listening" -
this is a Gate 3 check, but the symptom (timeout) had ALREADY ruled
out anything past Gate 1. Lesson: under time pressure, it is easy to
default to a generic "check the thing" instinct instead of applying
the specific model already built - the symptom itself should
immediately narrow which gate to check, skipping irrelevant layers
entirely rather than checking everything in sequence.

### Scenario 2: Teammate reports "refused," insists Security Group is fine
Correct approach: "refused" rules out Gate 1 BY DEFINITION - the
teammate's claim that the Security Group hasn't changed is actually
CONSISTENT with the evidence, not something to argue with. Trust the
symptom's implication and go straight to Gate 2 (ufw) or Gate 3 (the
app itself) - ss -tuln is the single most decisive first check (per
P13's lesson: it can make checking ufw entirely unnecessary if nothing
is even listening). ANSWERED CORRECTLY AND QUICKLY.

### Scenario 3: 1-in-3 failures with 3 backends, refresh fixes it
Correct approach: recognize "1 in 3 fails" as a strong numeric
pattern-match against having exactly 3 backend instances - points to
ONE specific unhealthy backend in the round-robin rotation, with
refresh "fixing it" simply by re-routing to a different, healthy
instance next time (not because anything was actually repaired). Next
step: test each backend individually (curl directly to each port) to
isolate the specific broken instance, then investigate it (likely a
crash-loop pattern from P14, given the intermittent, self-recovering-
on-retry nature). ANSWERED CORRECTLY after clarifying the reasoning.

### Overall Result
3/3 scenarios reached the correct conclusion. One genuine, useful
mistake caught under time pressure (Scenario 1: applying a Gate 3
check to a Gate 1 symptom) - a real, common interview stumble worth
having already made once here, in practice, rather than for the
first time in a real interview.

### Key Takeaway
Under time pressure, the instinct to "just check things" can override
already-built diagnostic models - the discipline is to let the
SYMPTOM ITSELF immediately narrow which layer to investigate (timeout
= Gate 1 only; refused = Gate 2/3 only), rather than defaulting to a
generic checklist. Numeric patterns in a reported symptom (e.g. "1 in
3" matching exactly 3 backend instances) are often a direct, fast clue
worth pattern-matching against known infrastructure counts immediately.

## M04-MINI - Real Fix for the Session's Recurring Reboot Problem

### The Problem This Solves
Across this entire module, EC2 reboots repeatedly killed
nohup/--daemon-backed processes, causing real incidents in P09, P11,
P12, P14, P16, P17, and P21 - every one required manual restart after
discovery via ss -tuln returning blank and uptime showing a recent
reboot.

### Root Cause of Why nohup/--daemon Never Actually Fixed It
Both nohup and gunicorn's --daemon flag only detach a process from
the CURRENT TERMINAL SESSION - neither registers the process with
systemd, so neither survives an actual machine reboot, which wipes
all running processes regardless of how they were started. Only
Nginx survived reboots automatically all module, because it alone was
a real systemd service.

### Real Fix: Proper systemd Service Files
Created /etc/systemd/system/checkout-backend-{1,2,3}.service for each
Gunicorn instance, with:
- Restart=always: automatically relaunches the process on ANY exit
  (crash OR reboot)
- StartLimitBurst=5 + StartLimitIntervalSec=60: caps restart attempts
  to 5 within 60 seconds, then gives up - a deliberate safety net so
  Restart=always doesn't SILENTLY MASK a genuinely broken, persistently
  crashing app by endlessly relaunching it forever (the exact
  crash-loop pattern studied in P14/P16) - balances real recovery
  against hiding a real bug.
- WantedBy=multi-user.target + systemctl enable: ensures the service
  starts automatically at boot, not just when manually started once.

### Real, Definitive Proof
Deliberately rebooted the EC2 instance (sudo reboot) as a genuine
test. After reboot: uptime showed "up 1 min," and ALL 3 backends were
ALREADY alive and responding correctly - zero manual intervention
required. This is the single most valuable verification in this
module - it retroactively would have prevented every reboot-related
incident encountered across P09 through P21.

### Key Takeaway
The fix for "background processes die on reboot" was never a better
backgrounding trick (nohup, --daemon, screen, tmux) - all of these
share the same fundamental limitation. The only real fix is registering
the process as an actual systemd service, which is exactly why Nginx
never needed manual recovery all module while every hand-started Flask/
Gunicorn instance did.
