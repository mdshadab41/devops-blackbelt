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
