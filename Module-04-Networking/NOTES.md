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
