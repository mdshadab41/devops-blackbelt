# Module 01 — Linux + Bash Scripting — Revision Sheet

## Disk Investigation
- `df -h` → filesystem-level usage (which mount is full)
- `du -h --max-depth=1 <path> | sort -rh` → drill down one level at a time, biggest first
- `du -m` → force MB output instead of mixed units
- `2>/dev/null` → suppress permission-denied noise during investigation
- `ls -lhS <path>` → find large individual files (du can miss single large files at a glance)

## Process Management
- `top` → live view; `q` to quit
- `pgrep <name>` → find PID by name; `pgrep -f "pattern"` → match full command line (needed for generic names, names >15 chars)
- `kill <PID>` → SIGTERM (polite, can be ignored/trapped) — always try first
- `kill -9 <PID>` → SIGKILL (forceful, cannot be trapped) — last resort only, skips cleanup
- `pgrep -f "x" | xargs kill -9` or `kill -9 $(pgrep -f "x")` → one-line find-and-kill

## Permissions
- `ls -l` → read the 9-character permission string: owner/group/others × read/write/execute
- "Permission denied" has TWO possible causes: (1) execute bit missing → `chmod +x`, (2) wrong owner → `chown user:group`
- Only the file's owner (or root) can `chmod`/`chown` it
- NEVER default to `chmod 777` — violates least privilege, hides root cause

## Bash Syntax Gotchas
- NO spaces around `=` in variable assignment (`VAR=value`, not `VAR = value`)
- `$VAR` to read a variable; bare `VAR` is just literal text
- Undefined/mistyped variables silently expand to empty string — NO error thrown
- `[ "$VAR" -ge N ]` needs spaces around brackets and quotes around the variable
- `[[ "$VAR" =~ ^[0-9]+$ ]]` → validate a variable is a clean integer before using it in math
- `for x in $VAR` loops over $VAR as ONE item; `for x in $VAR/*` expands wildcard, loops over each item inside

## Scripting Patterns
- `$(command)` → capture command output into a variable
- `read VAR1 VAR2 <<< "$(command)"` → split output into multiple variables at once
- `exit 0/1/2` → OK / WARNING / CRITICAL-or-UNKNOWN (standard monitoring convention)
- `set -e` → script stops immediately on any command failure
- `top`'s `%Cpu(s)` line is the key diagnostic:
- Swap used doesn't drop to 0 automatically after pressure clears — normal behavior, not a bug
## Incident Investigation Method (ties everything together)
4. Check disk (`df -h`, `du` drill-down) — a very common hidden cause
6. Verify the fix actually worked with real evidence, not assumptions
7. Write the RCA — every real incident ends with documentation5. Verify any fix is safe BEFORE applying it (ownership, `lsof`, timing correlation)
2. Check logs first (fast, often has direct clues)
3. Check CPU/memory (`top`, `free`) — rule these in/out
1. Confirm the actual symptom (don't assume)
- Swap setup: `fallocate` → `chmod 600` → `mkswap` → `swapon`. Teardown: ALWAYS `swapoff` before `rm`

- `free -m` → check `available` (not raw `free`) for realistic memory usage; check `Swap: used` to confirm swap-driven slowdowns
  - High `id` but elevated `wa` → I/O-bound, often memory pressure forcing swap
  - High `us`/`sy`, near-0 `wa`, near-0 `id` → CPU-bound
- `uptime` → load average, quick first signal (doesn't say WHAT kind of busy)

## Performance / Bottleneck Diagnosis
- Standard investigation chain: `grep` (filter) → `awk` (extract) → `sort | uniq -c` (summarize) → conclusion
- `trap cleanup EXIT` → guarantees cleanup runs on EVERY exit path (success, failure, interrupt) — NOT the same as cleanup code at the bottom of a script, which only runs on the happy path
- `sed 's/find/replace/'` → substitute text; doesn't modify file unless `-i` used
- `awk '{print $N}'` → extract column N (whitespace-separated by default)
- `sort | uniq -c` → count unique values (MUST sort first — uniq only collapses ADJACENT duplicates)
- `mktemp` → creates a safely unique temp file
- `grep "A.*B"` → both patterns must appear on the same line, A before B
- Integer math `$(( ))` → multiply BEFORE dividing to avoid precision loss (no decimals supported)
- `grep "pattern" file` → filter matching lines; `-c` → count matches directly

## Text Processing

## File Operations
- A script without `set -e` can print false "success" even after a real failure — visibility and honesty are two SEPARATE problems, both must be fixed
- `>> logfile 2>&1` → redirect stdout to file, then redirect stderr to wherever stdout now points (order matters)
- `find "$DIR" -name "pattern" -mtime "+$DAYS" -delete` → safe age-based cleanup (safer than piping to `rm`)
- Cron gives NO visibility into output/errors by default — both stdout and stderr vanish silently
## Cron

- Always verify with `cat`/`ls -la` before running an edited script — don't trial-and-error blindly
- `mkdir -p` → creates nested dirs, doesn't error if already exists
