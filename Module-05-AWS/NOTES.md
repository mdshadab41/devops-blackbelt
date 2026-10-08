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


## M05-P03: IAM foundations (users, groups, roles, policy language)

**What I did:**
- Discovered an existing IAM user `monitor-admin` (console login), separate
  from the EC2 role used all session — confirmed via ARN prefix (AIDA = user,
  AROA = role)
- Found `monitor-admin` has AmazonEC2FullAccess, AmazonS3FullAccess, and
  IAMUserChangePassword attached DIRECTLY to the user (not via a group) —
  `list-groups-for-user` returned empty. Anti-pattern: best practice is
  users -> groups -> policies, not policies glued to individuals.
- Fetched AmazonS3FullAccess policy JSON: Action ["s3:*", "s3-object-lambda:*"],
  Resource "*" — confirmed FullAccess means literally every action, every resource
- Wrote a least-privilege S3 policy from scratch (paper exercise, nothing
  attached to any real resource):
  Allow s3:GetObject + s3:ListBucket, scoped to one bucket

**Real mistakes made and corrected (own work, not copied):**
- First draft put ARNs in the Action field and "*" in Resource — backwards.
  Corrected: Action = verbs (API calls), Resource = nouns (what they act on).
- Missing JSON quotes/commas on first syntax attempt — fixed.

**Concepts learned:**
- IAM ARN prefixes: AIDA = user, AROA = role, AKIA = access key
- Bucket-level actions (ListBucket) need the bare bucket ARN; object-level
  actions (GetObject) need the ARN + /*. Using only one breaks the other —
  this is the root cause behind the P17 S3 Access Denied incident.
- Policies attached directly to a user vs. via a group is a real audit
  finding — groups make permission management scale across a team.

**Interview tips:**
- Be able to write Effect/Action/Resource JSON from memory, correctly
  quoted, on a whiteboard or in a live coding round
- Explain bucket-ARN vs bucket-ARN/* distinction without hesitating
- Know how to identify user vs role vs access-key just from an ID prefix


## M05-P04: S3 fundamentals (versioning, encryption, lifecycle)

**What I did:**
- Created bucket `devops-blackbelt-806528484602` (used account ID to
  guarantee global uniqueness — S3 bucket names are unique across ALL
  AWS accounts worldwide, not just mine)
- Enabled versioning, uploaded the same key twice, confirmed via
  `list-object-versions` that both versions exist simultaneously with
  separate VersionIds
- Deleted the object normally (`aws s3 rm`) — proved this only adds a
  DeleteMarker, doesn't touch real data. Download 404'd, but both real
  versions were still listed underneath
- Recovered the "deleted" file by deleting the DeleteMarker's own
  VersionId — download worked again, correct content returned
- Checked encryption: SSE-S3 (AES256) was already active with NO
  configuration from me — AWS made this the automatic default for all
  new buckets since 2023
- Applied a lifecycle rule (`NoncurrentVersionExpiration`, 30 days) to
  auto-delete old versions and control the storage-cost growth that
  versioning otherwise causes

**Concepts learned:**
- Bucket names are globally unique across every AWS account on Earth —
  not just within my account
- Many `put-*` CLI commands are silent on success — always verify with
  a matching `get-*` call rather than assuming success from no output/error
- Versioning ≠ backup by itself — it protects against accidental
  overwrite/delete, but without a lifecycle rule, EVERY overwrite in an
  active bucket accumulates full-size copies forever, creating a hidden,
  compounding storage cost that doesn't show up in a casual bucket listing
- SSE-S3 (AES256) is now AWS's zero-config default; SSE-KMS (customer-
  managed keys, more control, more cost) is the alternative, covered in P13

**Interview tips:**
- Be able to explain the delete-marker mechanism precisely: a normal
  delete on a versioned bucket doesn't remove data, it adds a marker
  that hides the object until removed
- Know why lifecycle rules matter specifically MORE for versioned
  buckets than non-versioned ones (unbounded silent storage growth)
- Know that SSE-S3 is now default-on, so "is my bucket encrypted?" isn't
  automatically a red flag anymore — the real question is which type


## M05-P05: EC2 lifecycle, EBS snapshots, AMIs, IMDSv2

**What I did:**
- Confirmed the instance has exactly one EBS volume (20GB, gp3) — matches
  the Module 03 permanent resize noted in STATUS.md
- Created a manual snapshot of the volume — watched it go from pending/0%
  to completed/100% in real time, proving snapshots copy data asynchronously
  in the background, independent of any command watching them
- Learned the hard way: `aws ec2 wait` can be interrupted (exit code 130 =
  Ctrl+C), which looks like "nothing happened" but the underlying job keeps
  running regardless — checked real progress (83%) even after the wait died
- Created a full AMI directly from the running instance using `--no-reboot`,
  understood the tradeoff: default behavior reboots the instance for
  filesystem consistency; `--no-reboot` avoids downtime but risks slightly
  less consistency if something was mid-write
- Noted the volume is NOT encrypted (`"Encrypted": false`) — a real audit
  finding, likely to surface again in the P21 Prowler scan

**Concepts learned:**
- EBS volume and EC2 instance are separate resources with separate
  lifecycles — this is *why* data survives stop/start, and why volumes
  can be resized without rebuilding the instance
- Snapshot = raw disk backup (incremental, cheap after the first one).
  AMI = full launch recipe built from a snapshot, includes OS/software/
  config metadata needed to boot a brand-new identical instance
- IMDSv2 exists specifically to block SSRF-based credential theft: IMDSv1
  allowed a plain, unauthenticated GET to return live role credentials.
  A vulnerable web app that fetches attacker-supplied URLs (SSRF) could be
  tricked into fetching the metadata endpoint FROM INSIDE the instance,
  handing an attacker real AWS credentials with no direct server access
  needed. IMDSv2's PUT-token requirement blocks most SSRF exploitation
  because attackers usually only control a GET request's target, not a
  PUT with a custom header. (Real-world precedent: Capital One 2019 breach)

**Interview tips:**
- Be able to explain snapshot vs AMI distinction precisely, not just
  "they're both backups"
- Know the SSRF + IMDSv1 attack chain end-to-end — this is a genuinely
  common AWS security interview question
- Mention unencrypted EBS volumes as a real audit red flag



**Cleanup:**
- Deregistered the AMI and deleted BOTH snapshots (the AMI's own auto-created
  snapshot, separate from my original manual one) — confirmed empty via
  `describe-images`/`describe-snapshots` afterward
- Real lesson: deregistering an AMI does NOT delete its underlying snapshot
  automatically — they're independent billable resources. A common real
  cost leak is deregistering old AMIs and forgetting the snapshot underneath
  keeps billing indefinitely
- Decision: cleaned up rather than kept as a DR baseline, since this was a
  learning exercise, not an active production safeguard
## M05-P06: Write a least-privilege IAM policy from scratch

**What I did:**
- Created a real IAM policy (`devops-blackbelt-s3-readonly`) from the JSON
  drafted on paper in P03: Allow s3:GetObject + s3:ListBucket, scoped to
  `devops-blackbelt-806528484602` (both bucket ARN and /* object ARN)
- Created a separate role (`devops-blackbelt-s3-readonly-role`) with its own
  trust policy, rather than touching `monitor-admin` or the EC2 role
- Used `aws iam simulate-custom-policy` to dry-run the policy before
  attaching it for real — confirmed GetObject/ListBucket allowed,
  DeleteObject/PutObject implicitDeny
- Attached the policy to the role, assumed the role via STS, and proved
  BOTH sides live against real AWS:
  - Allowed: `aws s3 ls` and `aws s3 cp` (download) succeeded
  - Denied: `aws s3 cp` (upload) and `aws s3 rm` both failed with precise
    AccessDenied errors naming the exact action, resource, and identity

**Real incident hit (not scripted):**
- Tried extracting AccessKeyId/SecretAccessKey/SessionToken via three
  separate `aws sts assume-role --query ...` calls — two of the three
  variables silently ended up empty (length 0), even though the plain
  assume-role call clearly returned all three fields. Diagnosed via
  `${#VAR}` length checks rather than guessing.
- Worse: once AWS_ACCESS_KEY_ID got set with no matching secret key, EVERY
  subsequent AWS CLI call (including diagnostic ones) broke, because the
  CLI prioritizes explicit env-var credentials over the EC2 instance role,
  even when those env vars are incomplete. Had to `unset` all three
  variables to fall back to the instance role before anything worked again.
- Fix: capture the full `assume-role` JSON response ONCE into a variable,
  then parse all three fields from that single response with Python,
  instead of three separate CLI calls.

**Concepts learned:**
- Trust policy vs. permissions policy are different things: trust policy
  (AssumeRolePolicyDocument) controls WHO can become the role; permissions
  policy controls WHAT the role can do once assumed. A role can have a wide
  trust policy and no permissions (harmless), or tight trust and broad
  permissions (also harmless from an access standpoint) — both parts matter
  independently.
- The IAM policy simulator is useful but NOT a perfect substitute for a
  real API call — it can return `allowed` for an action even when tested
  against a resource ARN that doesn't match the action's real-world
  scope (e.g., ListBucket against an object ARN still simulated as allowed
  because the policy's Resource array contains BOTH ARNs in one statement).
  Real proof only comes from an actual authenticated API call.
- Explicit AWS_* environment variables always take priority over IMDS role
  credentials in the CLI's credential chain — a partially-set environment
  can silently break ALL subsequent calls, not just the one you're debugging.
- AccessDenied error messages in S3/IAM are precise and self-documenting:
  they name the identity, the action, the resource, and the reason — this
  is the foundation of debugging P16 (IAM Permission Denied incident).

**Interview tips:**
- Be able to explain trust policy vs permissions policy without conflating
  them — a very common point of confusion
- Know that the AWS CLI credential chain checks environment variables
  before instance role/IMDS — explains a whole class of "why did my AWS
  CLI suddenly break" bugs
- Be ready to read a real AccessDenied message and extract the action,
  resource, and identity from it cold, without AWS's console UI


## Quick reference: Security Group vs NACL vs ufw/iptables

- **Security Group** — AWS firewall, instance-level, stateful, allow-only
  (no explicit deny), configured via AWS API/console/CLI, blocks traffic
  before it ever reaches the instance.
- **NACL (Network ACL)** — AWS firewall, subnet-level, stateless (inbound
  and outbound rules evaluated separately), supports both allow and deny,
  applies to everything in the subnet regardless of instance.
- **ufw/iptables** — OS-level firewall, stateful, allow and deny,
  configured by logging into the instance itself; only works if the OS
  is running and the firewall service is active.

**Order of enforcement:** Internet → IGW → Route Table → NACL (subnet) →
Security Group (instance) → ufw/iptables (OS) → application.


## M05-P07: Custom VPC from scratch (explored default VPC first)

**What I did — explored the default VPC:**
- Found the default VPC (172.31.0.0/16) and its 3 subnets, one per AZ
  (ap-south-1a/b/c), each a /20
- Learned manual CIDR math: /20 = 4096 addresses, calculated which subnet
  my instance's IP (172.31.13.66) falls into by hand, verified correct
- Discovered my instance's subnet had NO explicit route table association
  — it silently inherits the VPC's main route table (a real, non-obvious
  AWS default)
- Traced the main route table: local route (172.31.0.0/16) + internet
  route (0.0.0.0/0 -> IGW) — this is literally what makes a subnet "public"
- Worked through the full SSH reachability chain: IGW + route table +
  public IP + Security Group + ufw all have to independently allow traffic
  — explained why SSH "just worked" all module without me setting anything
  up, because the default VPC does ALL of this automatically

**What I did — built a custom VPC by hand:**
- Created VPC `vpc-0a8a0fbdabe47335b` (10.0.0.0/24, 256 addresses)
- Created public subnet (10.0.0.0/26, ap-south-1a) and private subnet
  (10.0.0.64/26, ap-south-1b) — proved no CIDR overlap
- Created and attached an Internet Gateway (confirmed attaching is a
  SEPARATE step from creating — not automatic, unlike the default VPC)
- Created a route table, confirmed the "local" route is automatic but the
  internet route (0.0.0.0/0 -> IGW) must be added manually
- Explicitly associated the route table with the public subnet
- Enabled auto-assign public IP on the public subnet
  (MapPublicIpOnLaunch) — confirmed false by default, even after routing
  was correctly wired
- Created a VPC-scoped Security Group (learned Security Groups can't span
  VPCs, since ambiguous overlapping CIDR ranges across VPCs would make
  rule references meaningless)
- Launched a real test instance into the public subnet — confirmed it
  got a public IP automatically and reached `running` state, proving the
  whole chain works end-to-end
- Terminated the test instance immediately after proof (cost control) —
  confirmed the auto-assigned public IP vanished with no cleanup needed,
  unlike an Elastic IP which would keep billing until released

**Decision:** kept the VPC/subnets/IGW/route table/Security Group, since
all of these are genuinely free while idle — only a running instance or
a NAT Gateway would cost money, and neither currently exists in this VPC.
Did NOT create a NAT Gateway (private subnet has no internet route) to
avoid its hourly + data transfer cost; understand the concept without
paying to run one continuously.

**Concepts learned:**
- CIDR math: /n means 32-n host bits, 2^(32-n) addresses. AWS reserves 5
  addresses per subnet for internal use regardless of subnet size.
- A subnet is "public" only because its (explicitly or implicitly
  inherited) route table sends 0.0.0.0/0 to an IGW — never because of a
  name or tag
- Security Group (instance-level, stateful, allow-only) vs NACL
  (subnet-level, stateless, allow+deny) vs ufw/iptables (OS-level,
  stateful, allow+deny) — three independent layers, each catching
  different misconfiguration mistakes
- sshd is the actual OpenSSH server process/daemon — the final
  APPLICATION-level check (does this key match?), separate from every
  earlier NETWORK-level check (can the packet even arrive?)
- VPC/subnet/route table/IGW/Security Group cost nothing while idle;
  only running compute (instances) and specific managed services (NAT
  Gateway, Elastic IP when unattached) actually bill

**Interview tips:**
- Be able to draw the full packet path from memory: Internet -> IGW ->
  Route Table -> NACL -> Security Group -> ufw/iptables -> sshd
- Know that attaching an IGW is a separate step from creating one, and
  that route table association is explicit-or-inherited-from-main, never
  automatic for a non-default VPC
- Understand why NAT Gateway exists conceptually even without having one
  running: private subnet needs OUTBOUND-only internet access without
  being reachable FROM the internet
