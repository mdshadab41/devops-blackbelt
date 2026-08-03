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
