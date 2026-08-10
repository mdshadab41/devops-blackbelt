# Module 01 — Notes

## M01-P01 — Disk Usage Investigation

- `du -h --max-depth=1 <path> | sort -rh` → drill down disk usage, one level at a time
- `2>/dev/null` → suppress permission-denied noise during investigation
- `$(command)` → capture command output into a variable
- `[ "$VAR" -ge N ]` → numeric comparison in bash (needs the `$`, needs quotes around the variable)
- `[[ "$VAR" =~ ^[0-9]+$ ]]` → validate a variable is a clean integer before trusting it in math
- `exit 0/1/2` → standard health-check convention: OK / WARNING / UNKNOWN-failure
- `chmod +x` → required before a script file can be run directly

## M01-P02 — Process Hunting (Find & Kill Runaway Process)

- `pgrep <name>` → find PID by process name (only works well if name is specific enough)
- `pgrep -f "pattern"` → match against full command line (needed for generic names like `bash`, `python`)
- `kill <PID>` → SIGTERM, polite shutdown request, always try first
- `kill -9 <PID>` → SIGKILL, forceful termination, no cleanup — use only if SIGTERM fails
- `kill` does NOT read PIDs from piped input — needs `xargs` or `$(...)` to combine with `pgrep`
- `pgrep -f "pattern" | xargs kill -9` or `kill -9 $(pgrep -f "pattern")` → one-line find-and-kill, useful in scripts
- Always start a fresh target process before testing a second kill method — testing against an already-dead process gives misleading errors

## M01-P03 — Permissions Incident (Permission Denied)

- "Permission denied" running a script can have TWO different root causes:
  1. Execute bit not set at all → fix with `chmod +x file`
  2. Execute bit set, but for the wrong owner/group → fix with `chown user:group file`
- Always run `ls -l file` FIRST and check both:
  - Is there an `x` anywhere in the permission string?
  - Does the owner/group match the user trying to run it?
- Never default to `chmod 777` — grants read/write/execute to EVERYONE, violates least-privilege, and hides the real root cause instead of fixing it
- Only the file's owner (or root) can change its permissions — `chmod` on a file you don't own fails with "Operation not permitted"
- `printf '...\n'` is more reliable than `echo -e` for writing multi-line scripts to a file

## M01-P04 — Log Rotation & Cleanup Script

- `date +%Y-%m-%d_%H-%M-%S` → timestamp with second precision, prevents filename collisions
- Date-only filenames (`app.log.2026-08-04`) cause SILENT DATA LOSS if script runs more than once per day — `mv` overwrites existing files with no warning
- `mv` never warns before overwriting an existing destination file — always ensure destination filenames are unique
- `find "$DIR" -name "pattern" -mtime "+$DAYS" -delete` → safe, direct way to clean up old files by age (safer than piping to `rm`)
- `set -e` → script stops immediately if any command fails, prevents cascading errors from a script continuing after a failure
- Explicit precondition checks (`if [ ! -f "$FILE" ]; then ... exit 1; fi`) catch problems early with a clear message, instead of relying on a later command to fail cryptically
- Always verify a script's file content with `cat` before re-running after an edit — faster than trial-and-error debugging

## M01-P05 — Debug the Broken Backup Script

- No spaces allowed around `=` in bash variable assignments (`VAR=value`, not `VAR = value`) — spaces make bash treat the first word as a command to run, not a variable name
- `mkdir` errors if the target already exists; `mkdir -p` creates it only if needed, and also creates nested/missing parent folders in one go
- `cp source/* destination` requires `destination` to already exist AS A DIRECTORY when copying multiple files — a non-existent path as destination will fail
- Real debugging technique: trace what each line of a script actually produces, then check whether the NEXT line's assumptions are satisfied by that — don't just guess or run trial-and-error

## M01-P06 — Cron Job Silently Failing

- Cron gives NO visibility into output or errors by default — both stdout and stderr vanish unless explicitly redirected
- `>> logfile 2>&1` → redirect stdout to a file (append), then redirect stderr to wherever stdout is now pointing (the same file). Order matters — this exact sequence is required.
- A script without `set -e` can keep running after a real failure and print a false "success" message — always verify exit codes, not just printed text
- Real incident investigation technique: compare file timestamps against the current time to detect a job that's silently stopped updating, even when there's no visible error anywhere
- Two separate concerns: VISIBILITY (can you see the failure?) and HONESTY (does the script correctly report failure?) — fixing one doesn't fix the other; production scripts need both


## M01-P07 — Multi-Check Health Monitoring Script

- Real monitoring scripts check MULTIPLE things and combine results into ONE overall status — never average severities, always report the WORST one found
- CRITICAL (highest severity) can be set directly, no guard needed — it's always safe since nothing is worse
- WARNING (middle severity) needs a guard (`if [ "$STATUS" -lt 1 ]`) — otherwise it could downgrade an already-worse CRITICAL result from an earlier check
- `free -m` → memory in MB; use `available` column (not `free`) for realistic usage %, since Linux uses spare RAM for reclaimable disk cache
- `read VAR1 VAR2 <<< "$(command)"` → splits command output into multiple variables at once
- Integer math in bash (`$(( ))`) — multiply BEFORE dividing to avoid losing precision (no decimals supported)
- `pgrep <name>` used directly in `if pgrep name > /dev/null; then` — pgrep's own exit code (0=found, 1=not found) can drive the if/else directly, no need to capture output
- `pgrep` process name matching is limited to ~15 characters — use `-f` for longer/full command-line matches
- One combined health-check script > multiple separate scripts — gives monitoring systems ONE clear signal instead of fragmented alerts for what might be one root cause

## M01-P08 — "Server Is Slow" Bottleneck Investigation

- Systematic order for investigating slowness: CPU → Memory → Disk I/O → specific process (broad to narrow, same top-down approach as disk investigation in M01-P01)
- `uptime` / load average → quick first signal something's busy, but doesn't say WHAT kind of busy
- `top`'s `%Cpu(s)` line is the key diagnostic:
  - High `us`/`sy`, near-0 `wa`, near-0 `id` → CPU-bound (real work maxing out the CPU)
  - High `id` but elevated `wa` → misleading at a glance ("CPU has headroom") but actually I/O-bound — often caused by memory pressure forcing swap usage
- `free -m` Swap row → cross-check swap `used` alongside `top`'s `wa` value to confirm memory-pressure-driven slowdowns
- Once memory pressure is relieved, swap `used` does NOT automatically return to 0 — Linux only moves data back from swap when something actively needs it again; lingering swap usage is normal, not a bug
- Swap setup: `fallocate -l SIZE /swapfile` → `chmod 600` (security, RAM can hold sensitive data) → `mkswap` (format) → `swapon` (activate)
- Swap teardown: ALWAYS `swapoff` before `rm` — deleting an active swap file without disabling it first can cause real problems
- `stress --vm 1 --vm-bytes SIZE --timeout Ns` → controlled, safe way to simulate memory pressure for testing (installed via `apt install stress`)
- Same symptom ("slow") can have completely different — even opposite — CPU profiles depending on true root cause; never diagnose from one signal alone

## M01-P09 — Text Processing (grep/awk/sed) on Log Files

- `grep "pattern" file` → find matching lines; `-c` → count matches directly (no need to pipe to `wc -l`)
- `grep "A.*B" file` → matches lines containing A, followed eventually by B (both conditions on one line)
- Chaining `grep | grep` → progressively narrows results, same idea as combining filters
- `awk '{print $N}'` → extract column N from each line (columns are whitespace-separated by default)
- `sort | uniq -c` → classic pattern to count occurrences of unique values — MUST sort first, since uniq only collapses ADJACENT duplicates
- `sed 's/find/replace/'` → substitute text; does NOT modify the file unless `-i` flag is used (safe by default, just transforms output)
- Standard log investigation pattern: `grep` (filter) → `awk` (extract field) → `sort | uniq -c` (summarize/count) → draw conclusion
- A concentrated cluster of one error type, in one time window, on one/two endpoints → strong signal of a SINGLE root cause, not multiple unrelated issues

## M01-P10 — Production RCA: Service Down (Full Investigation)

- Full end-to-end incident investigation combining ALL prior Module 01 skills: symptom confirmation → log check → CPU/memory check → disk check → drill-down → safe verification → fix → recovery verification
- A process disappearing with no error trace in its own log often points to an EXTERNAL cause (resource exhaustion, kill signal), not an internal crash
- Disk-full incidents can silently take down unrelated services — check disk usage early, not last, in "service is down" investigations
- Verify a file is safe to delete before removing it: check ownership, `lsof` (is it open?), timing correlation, and naming pattern
- Real incidents always end with a written RCA — the deliverable isn't just "fixed it," it's the documented reasoning and prevention plan

