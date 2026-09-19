# Module 04 — Networking — Revision Sheet

## Section 1: Core Networking Model (P01-P05)

**Socket.** A socket is the unique combination of four things: your
computer's address, a temporary "door number" your side uses for this
one connection, the server's address, and the server's fixed door
number. The temporary door number (called an ephemeral port) changes
every time you start a new connection, even to the same server — this
is exactly what lets one machine run several conversations at once
(like multiple browser tabs to the same website) without them getting
mixed up. The server, by contrast, always uses the same fixed door
number, because visitors need to be able to find it reliably every
time.

**Loopback (127.0.0.1) vs 0.0.0.0.** 127.0.0.1 means "myself" — a
message sent here never actually leaves the machine at all, it's a
shortcut for talking to a program on the same computer. 0.0.0.0 means
"listen for anyone, from anywhere," including real outside traffic.
This distinction matters constantly in real work: a backend app should
usually be set to 127.0.0.1 (only reachable through a trusted proxy in
front of it), while the proxy itself needs 0.0.0.0 (so the outside
world can actually reach it).

**Refused vs Timeout — the single most useful diagnostic signal in
this whole module.** If a connection fails FAST with "refused," it
means the request genuinely reached the other machine, and something
there actively said no (nothing was listening, or the app rejected
it). If a connection fails SLOWLY, eventually timing out, it means the
request never arrived anywhere at all — it was silently dropped
somewhere along the way, and your own computer is just waiting for a
reply that will never come, unable to tell the difference between
"still in transit" and "never arriving." This one distinction tells
you immediately which part of the system to investigate, without
checking everything one by one.

**DNS and TTL.** Turning a website name into a real address involves
your computer first checking if it already remembers the answer
(caching), and if not, asking around until it finds the true, current
answer. Every answer comes with a TTL (time-to-live) — how long it's
allowed to be remembered before it must be asked again. A SHORT TTL
means changes take effect everywhere quickly, at the cost of asking
more often; a LONG TTL is more efficient day-to-day, but slow to
update if something changes (like a migration to a new server).

**TCP vs UDP.** TCP is a careful, connection-based way of sending data
— it performs a 3-step handshake before any real data moves (SYN,
SYN-ACK, ACK), and guarantees every piece of data arrives, correctly,
in the right order, automatically resending anything lost. This makes
it slower but reliable, which is why ordinary web traffic and chat
messages use it — losing a chat message silently would be unacceptable.
UDP skips the handshake and all the guarantees entirely — it just
fires data and moves on. This makes it faster, at the cost of some
data possibly just vanishing with nobody noticing or fixing it. This
tradeoff is why live video calls, gaming, and DNS lookups use UDP — a
slightly glitchy video frame arriving on time beats a perfect frame
arriving late.

**Diagnostic toolkit.** `ss -tuln` shows what's actually listening on
which port and interface right now — the fastest way to check if an
app is even running. `nc -zv` tests whether a specific port is
reachable, without the overhead of a full request. `traceroute` shows
every network hop between you and a destination — importantly, a
silent hop (shown as `* * *`) does NOT necessarily mean that hop is
broken; many routers deliberately don't reply to this kind of probe
for security reasons, while still correctly forwarding real traffic.
`tcpdump` captures actual, real packets moving across the network —
the strongest possible evidence for what's genuinely happening,
useful for proving (not just assuming) whether traffic is arriving at
all.

## Section 2: The 3-Gate Diagnostic Model (P06-P13)

Every connection has to pass through three checkpoints, in order, and
only one blocked checkpoint is needed to stop it entirely:

**Gate 1 — Security Group (AWS, outside the instance entirely).** This
is checked before your request ever reaches the actual server. If
blocked here, the result is always a TIMEOUT, since the request never
gets a chance to reach anything that could respond.

**Gate 2 — ufw / OS firewall (inside the instance, but before the
app).** Only reached if Gate 1 already let the request through. If
blocked here, the result is REFUSED, since the operating system itself
is now actively rejecting it.

**Gate 3 — the application itself.** Only reached if Gates 1 and 2
both passed. If the app isn't running or isn't listening on that
port, the result is also REFUSED.

**The one-sentence rule that ties this together: timeout can only ever
happen at Gate 1. Every failure past Gate 1 shows up as refused, never
as a timeout — because something is now genuinely there to respond.**
This means the symptom alone (fast rejection vs. slow silence) tells
you immediately which gate to investigate, without needing to check
all three every time.

**Why ufw exists even with a Security Group already in place:** a
Security Group is often shared and deliberately broad (to serve many
teams or use cases at once), so it might allow more than any one
specific machine actually needs. ufw lets that one machine enforce its
own, tighter rules independently — so if the shared Security Group is
ever more permissive than ideal, this second, independent layer still
protects the machine. This is the same "defense in depth" idea as
binding an app to 127.0.0.1 even though a proxy already sits in front
of it — never rely on just one layer of protection.

**ufw is not a separate system from iptables — it's a simpler,
human-friendly interface that automatically generates real, low-level
iptables rules underneath.** This was proven directly by inspecting
iptables' own rule chains and finding ufw-generated entries there,
despite never running a raw iptables command.

**Critical lockout risk:** ufw ships disabled by default on cloud
servers, because if it shipped active with no rules configured, the
very first remote-access attempt would be blocked. Before ever
enabling it, you must explicitly allow remote access first — enabling
it without doing so instantly and often permanently locks you out of
your own session, with no easy way back in.

**nohup is not enough for real reliability.** Running a process in the
background with `&` or `nohup` only protects it from your terminal
session ending — it does NOT survive the entire server actually
rebooting, since a reboot wipes everything from memory regardless of
how the process was started. Real systems use a process supervisor
(systemd, Docker, Kubernetes) specifically because these automatically
relaunch a process after ANY kind of interruption, not just a
disconnected terminal — this was learned the hard way, repeatedly,
across multiple real incidents in this module.

## Section 3: Reverse Proxy, Load Balancing, and TLS (P06, P09, P10)

**Reverse proxy.** A reverse proxy (like Nginx) sits in front of the
real application and forwards requests to it on the visitor's behalf
— the outside world only ever talks to the proxy, never directly to
the app itself, which can stay hidden, be restarted, or be scaled
without visitors ever needing to know. This also means the app can
safely be bound to 127.0.0.1 (unreachable from outside directly),
since only the proxy, on the same machine, ever needs to reach it.

**Why passing a config's syntax checker doesn't mean it's correct.** A
checker only verifies the RULES of the language are followed — it has
no idea what you actually meant. A single wrong character (like `&`
instead of `$` in a variable reference) can be perfectly valid syntax
while doing something completely different from what was intended.
The only real way to catch this is to test actual behavior, not just
check for errors.

**Load balancing algorithms — three different tradeoffs, not one
"best" choice:**
- **Round-robin** (the default): cycles through backend servers in
  strict order. Fair in terms of how many requests each server gets,
  but NOT necessarily fair in terms of actual workload — a server
  stuck on one slow request still gets new requests forced onto it on
  schedule.
- **Least-connections:** sends new requests to whichever backend
  currently has the fewest active, in-progress connections — actually
  accounts for real load, not just request count. Only visibly
  different from round-robin when request processing times vary
  meaningfully.
- **IP-hash (sticky sessions):** always sends the same visitor's IP to
  the same backend, every time. Useful when a backend remembers
  something specific about that visitor (like an in-memory shopping
  cart) that other backends don't share — but sacrifices even traffic
  distribution to achieve this consistency.
All three were proven to automatically detect and route around a dead
backend without any manual intervention — this is a built-in health
check, not something that had to be separately configured.

**TLS/HTTPS.** Encryption works in two phases: first, a slow-but-very-
secure method (asymmetric encryption) is used briefly, just to safely
agree on a shared secret between the two sides, without an eavesdropper
being able to intercept that secret even if they capture the entire
exchange. Once that secret is safely agreed upon, both sides switch to
a much faster method (symmetric encryption) for the rest of the actual
conversation, since the slow method would be too costly for bulk data.

**Self-signed vs CA-signed certificates.** A self-signed certificate
provides completely real, working encryption — proven directly by
capturing real, correctly-negotiated encrypted traffic. What it does
NOT provide is any proof of identity — anyone can generate a
self-signed certificate claiming to be anyone, so it offers zero
protection against an impostor. A certificate from a real, independent
Certificate Authority (like Let's Encrypt) additionally proves that an
independent third party verified you genuinely control the domain in
question — this is why browsers only trust CA-signed certificates by
default, and why self-signed certificates are fine for your own
private testing but never acceptable for a real public-facing service.

## Section 4: Real Incident Patterns (P12-P16, P21)

**500 vs 502 — different problems, different fixes.** A 500 error
means the backend application is genuinely alive, received the
request, and its own code broke while handling it — but it still
managed to respond with an error page. A 502 error means the proxy in
front got NO valid response from the backend at all — the backend is
either completely dead, hung, or entirely unreachable. A single bug in
one route handler can only ever produce a 500 (the surrounding
framework catches it and keeps running) — producing a real 502
requires the ENTIRE backend process to die, not just one request to
fail. This means seeing a wave of 502s doesn't automatically mean "the
code has a bug" — it could equally mean the process itself crashed, or
that the proxy itself ran out of resources trying to reach a perfectly
healthy backend (see file descriptor exhaustion, below) — these need
completely different fixes.

**DNS "not resolving" — three genuinely different causes.**
Misconfiguration means the record itself was entered wrong at the
source — every resolver, once it catches up, will consistently agree
on the same WRONG answer, and no amount of waiting fixes this; the
record itself must be corrected. Propagation means the authoritative
sources of truth haven't finished syncing with each other yet — even a
completely fresh, uncached query can get different answers depending
on which specific source happens to be asked, and the fix here is
simply to wait. Caching means the true, correct answer already exists
everywhere, but some individual visitor's device is still holding onto
an old, unrefreshed copy from before — again, mostly a matter of
waiting out that copy's expiry, or manually clearing it. The fastest
way to tell these apart: ask "is this happening to literally everyone,
or just some people?" Everyone consistently affected points to
misconfiguration; only some affected points to propagation or caching,
which can then be told apart by querying a specific authoritative
server directly.

**File descriptor exhaustion.** Every open connection consumes a
limited internal resource on the server (a "file descriptor"), and a
proxy typically needs roughly two of these per request in flight at
once — one for the visitor's connection, one for the connection to the
backend. Under a sudden traffic spike, a server can run out of these
purely from having too many SIMULTANEOUS connections at once — not
from the total number of requests it has ever served. This looks
"random" and "intermittent" from the outside, but it's actually
completely deterministic — proven directly with a real load test that
reproduced genuine failures purely by exceeding this limit. Critically,
this kind of failure self-resolves the instant traffic drops back down,
with zero code changes or restarts needed, which is the key clue that
distinguishes it from a backend that's genuinely crashing and
restarting repeatedly (a crash loop), since a crash loop would keep
failing regardless of how much traffic there currently is.

**One symptom can hide multiple, unrelated problems.** In a real,
unguided investigation this module, a single reported "502 error" was
actually revealed to be two entirely separate, coincidental problems —
one because backend processes had died after a server reboot, and a
completely unrelated one because the server's public IP address had
also changed during that same reboot, making an otherwise-correct
investigation target the wrong address. The lesson: when evidence from
different tests stops fitting one single, unified explanation, that's
a signal to consider that more than one thing might genuinely be wrong
at once, rather than continuing to force every clue into one theory.

## Section 5: Architecture and Tool Tradeoffs (P19-P20)

**Why only the web tier should be directly reachable from the
internet.** In a proper multi-tier design, only the front-facing web
server sits in a subnet with direct internet access; the application
logic and the database live in separate, private subnets with no
direct internet route at all. This limits "blast radius" — if an
attacker fully compromises the internet-facing tier, the network
itself, not just application permissions, prevents them from
automatically reaching the database too. Each additional tier is a
genuine, independent obstacle.

**NAT Gateway — solving outbound-only access for private resources.**
Private-subnet resources sometimes still need to reach OUT to the
internet (downloading updates, calling external services), while
never being reachable via unsolicited INBOUND connections. A NAT
Gateway solves this because of a structural, not just configured,
guarantee: since the private resource always initiates the
conversation first (acting as the client), and the NAT Gateway only
ever relays responses to conversations that were already started from
the inside, there is no mechanism at all for a brand-new, uninvited
message from the internet to reach the private resource — it's not a
rule that could be accidentally misconfigured, it's how the mechanism
fundamentally works.

**Nginx vs HAProxy vs ALB.** Nginx began as a web server and later
gained proxy/load-balancing features — useful when you want one tool
to handle multiple jobs (serving files, TLS, proxying, load balancing)
at once. HAProxy was purpose-built from the start to do only load
balancing and proxying, often with more advanced tuning options, at
the cost of not being a general-purpose web server too. ALB is a fully
managed AWS service — not something you install or maintain at all;
AWS handles its scaling, patching, and availability automatically and
invisibly, at the cost of being limited to whatever configuration
options AWS exposes. This is a genuine "build vs buy" tradeoff: full
control and flexibility vs. zero operational burden — directly
informed by real, personal experience this module of manually
recovering self-hosted processes after multiple real server reboots,
something a managed service would never have required.

## Section 6: SSH and Identity (P08)

**Why splitting a key into a public and private half is safer than
one shared secret.** The private key stays only on your own laptop and
is never uploaded anywhere; the public half can be freely copied to as
many servers as needed, since it's mathematically impossible to work
backward from the public half to the private one. This means if a
server storing your public key is ever compromised, an attacker gains
nothing usable against your other servers using the same key pair —
the only genuine danger is the private key FILE itself being stolen
directly from your own laptop, which is a completely separate event
from any server being hacked.

**SSH config files and saved sessions solve typing convenience, not
address instability.** They let you save a shortcut instead of typing
a full connection command every time, but they do nothing about an
EC2 instance's public IP changing every time it's stopped and started
— that specific, real problem requires a static, unchanging address
(an AWS Elastic IP), a completely different fix for a completely
different problem.

**Verify assumptions instead of trusting them.** During this module,
an assumption that "SSH agent forwarding" explained a certain working
behavior was directly investigated and disproven with real command
evidence — the actual explanation turned out to be something else
entirely (HTTPS-based authentication, not SSH keys at all). The
broader lesson: the first plausible-sounding explanation isn't always
the correct one, and checking directly is what actually separates a
correct diagnosis from a lucky guess.

## Section 7: Measuring and Improving Latency (P16-P17)

**Why breaking total time into stages matters.** A single "it's slow"
number gives no actionable information. Breaking it into distinct
phases (how long the address lookup took, how long the connection
itself took, how long the server took to send back its first byte)
immediately points to which specific part of the system needs
attention — network distance, connection setup, or the application's
own processing time all have completely different fixes.

**Why testing from the wrong location gives dangerously false
confidence.** A test run from the same server being tested, or from
inside the same network, skips the exact part of the journey — the
real, external internet — that usually contains the actual delay. This
mistake happened multiple times in this module, producing suspiciously
fast, meaningless results that had to be caught and corrected by
explicitly verifying the actual machine the test was being run from
before trusting any "good" result.

**Why a "just for testing" server causes real slowness under genuine
traffic.** A basic development server is often built to handle only
one request at a time by design — under real, simultaneous traffic,
later requests have to wait in line even if their own individual work
would have been instant, and that waiting shows up to users as
latency, even though nothing is technically broken. Swapping to a
properly built production server that can genuinely handle multiple
requests in parallel was measured to cut this latency roughly in half
in this module, with zero changes to the actual application code —
proof that the serving infrastructure itself can be as significant a
bottleneck as the code running on it.

## Section 8: Getting a Real, Trusted Certificate (P18)

**Why a real domain name is required, not just a numeric address.** A
certificate's entire purpose is proving "this specific address
genuinely belongs to this specific owner" — a Certificate Authority
verifies this by checking domain ownership through DNS or file
verification, something a bare IP address (which has no persistent,
registrable owner in the same way) cannot support. This is a genuine,
real-world planning dependency that must be addressed before a real
launch — not something that can be discovered at the last minute.

**Why "no special flag needed" is the definitive proof of trust.**
When a tool like curl connects to a certificate successfully with no
special override flag required, it means a completely independent,
external judge — the tool's own built-in list of trusted authorities —
examined and accepted the certificate on its own, without you having
to vouch for it yourself. This is the exact, concrete evidence that
separates a genuinely trusted setup from a merely working one.

## Section 9: Quick-Recall One-Liners

- Refused = reached the machine and got rejected. Timeout = never
  reached the machine at all.
- 500 = the app is alive but broke on this one request. 502 = the
  proxy got nothing back from the app at all.
- Self-signed certificates encrypt perfectly well but prove nothing
  about identity — that requires a real, independent Certificate
  Authority.
- ufw is a friendly interface that generates real iptables rules
  underneath — not a separate system.
- nohup survives a disconnected terminal but never a full server
  reboot — only a real process supervisor does.
- A NAT Gateway's outbound-only behavior is structural, not just a
  configurable rule that could be misconfigured.
- A failure affecting exactly 1-in-N requests, with N backend servers,
  usually points to one specific broken instance in the rotation —
  not a systemic, widespread issue.
- Never trust a "great" latency result until you've confirmed you
  were actually testing from the location you meant to test from.
