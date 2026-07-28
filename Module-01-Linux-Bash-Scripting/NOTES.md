# Module 01 — Notes

## M01-P01 — Disk Usage Investigation

- `du -h --max-depth=1 <path> | sort -rh` → drill down disk usage, one level at a time
- `2>/dev/null` → suppress permission-denied noise during investigation
- `$(command)` → capture command output into a variable
- `[ "$VAR" -ge N ]` → numeric comparison in bash (needs the `$`, needs quotes around the variable)
- `[[ "$VAR" =~ ^[0-9]+$ ]]` → validate a variable is a clean integer before trusting it in math
- `exit 0/1/2` → standard health-check convention: OK / WARNING / UNKNOWN-failure
- `chmod +x` → required before a script file can be run directly
