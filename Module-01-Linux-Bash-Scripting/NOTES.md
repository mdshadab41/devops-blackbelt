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
