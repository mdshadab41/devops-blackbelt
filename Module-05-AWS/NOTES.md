# Module 05 — AWS

## M05-P01: Elastic IP — fixing the changing-IP problem

**Scenario:** Public IP changed 3+ times in a single Module 04 session,
permanently breaking a nip.io-based domain and forcing cert reissue.

**What I did:**
- Checked baseline: `aws ec2 describe-addresses` — no EIPs existed yet
- Allocated an EIP: `aws ec2 allocate-address` — got 15.252.212.136
  (different from the automatic IP, confirms EIPs come from a separate pool)
- Attached it: `aws ec2 associate-address --instance-id ... --allocation-id ...`
- Verified: `checkip.amazonaws.com` from inside the instance matched the EIP
- Verified: `describe-addresses` shows it correctly associated to my instance ID
- Stopped and started the instance via console — IP stayed 15.252.212.136
  both while stopped and after restart
- Reconnected via SSH with no host-key warning (proves same identity, new confirms IP survives)

**Real incidents hit (not scripted):**
1. IMDSv2 rejected a plain curl to the metadata endpoint with 401 Unauthorized
   — had to fetch a session token first (`PUT /latest/api/token`) and pass it
   as a header on every metadata request.
2. Console showed a stale/cached public IP after attaching the EIP — a full
   browser refresh fixed it. Lesson: don't trust console state without refreshing
   during network changes.
3. SSH appeared to "hang with zero output" — actual cause was an unanswered
   host-key confirmation prompt (first-ever connection to this new IP) combined
   with an incorrect key file path in earlier attempts. Verbose mode (`ssh -v`)
   and testing `ssh -V` alone helped isolate terminal-vs-network vs SSH-handshake
   layers.
4. Disabled the 3 checkout-backend systemd services (Module 04) to free RAM
   before Prowler-heavy work later in this module — used `disable --now`
   (not just `stop`) so they don't silently restart on the next reboot.

**Concepts learned:**
- SSH host key = server identity (tied to the disk/EBS volume, survives
  IP changes). Public IP = temporary mailing address. These are different
  things — `known_hosts` had 8+ old IPs mapped to the same host key fingerprint,
  proving it's the same server across all those Module 03/04 IP changes.
- Public IPv4 pricing (since Feb 2024): $0.005/hour for ANY public IPv4,
  Elastic or automatic, attached or not. An EIP only saves money over an
  automatic IP during hours the instance is stopped (no IP = no charge then).
- Decision: keeping the EIP (~$3.60/month) since I SSH in most days — cost of
  re-diagnosing IP changes exceeds the small monthly charge. Will revisit if
  I stop actively studying for 3+ days at a stretch.
- RAM check before this module: `free -h` "available" is the real number,
  not "free" (buff/cache is reclaimable). Backends used ~200-280MB combined
  across 9 gunicorn processes — freed for Prowler headroom later in module.

**Acceptance criteria met:**
- [x] Same public IP before and after stop/start
- [x] No unattached Elastic IPs in the region (describe-addresses confirms
      association to instance)

**Interview tips:**
- Know the actual current pricing model, not the old "attached = free" rule
- Be ready to explain host key vs IP as separate identity concepts
- Unattached/orphaned EIPs are a classic real-world cost leak — always
  mention checking for these in a cost-audit answer

## M05-P02: Identity and credentials (CLI, STS, IMDS role credentials)

**What I did:**
- Confirmed no `~/.aws/credentials` file exists on the instance
- `aws sts get-caller-identity` succeeded anyway — proved the instance
  authenticates via an assumed IAM role, not stored keys
- ARN showed `assumed-role/devops-blackbelt-ec2-role/i-068d097ced32d2ace`
  and UserId prefix `AROA...` — both confirm "this is a role", not a user
  (user prefix would be `AIDA...`, access key prefix `AKIA...`)
- Walked the IMDSv2 chain directly:
  1. PUT request to `/latest/api/token` — got a session token
  2. GET `/latest/meta-data/iam/security-credentials/` with the token header
     — returned the role name as plain text
  3. GET the same path + role name — returned AccessKeyId, SecretAccessKey,
     Token, and an Expiration timestamp (~6 hours out)

**Real incident (self-inflicted):** pasted the actual temporary credentials
into chat while documenting the output. Not a real breach since they're
short-lived and expire automatically, but a genuine lesson: never paste
AccessKeyId/SecretAccessKey/Token values anywhere outside the terminal —
describe the *shape* of credential output, never the real values, even
temporary ones.

**Concepts learned:**
- The CLI/boto3/Terraform all fetch role credentials from IMDS automatically
  and silently — this is why zero configuration was needed on this instance.
- Short-lived, auto-rotating credentials are a deliberate security design:
  they cap the exposure window if credentials ever leak (as just demonstrated),
  unlike a permanent IAM user's access key, which stays valid until manually
  revoked.
- Also visually re-learned from P01: terminal output can be easy to miss
  when it runs together with the previous prompt line — always scroll up
  and check carefully before concluding "nothing printed."

**Interview tips:**
- Be able to explain the full IMDS credential chain from memory: role
  attached → IMDSv2 token → role name → temporary creds with expiration
- Know why EC2 instance roles are the best-practice alternative to hardcoded
  access keys, and why short expiry windows matter even for accidental leaks
