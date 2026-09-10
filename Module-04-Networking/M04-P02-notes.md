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
