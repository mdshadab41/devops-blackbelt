# Module 01 — Linux + Bash Scripting — Revision Sheet (Detailed)

---

## 1. Disk Investigation

**The problem:** A server alerts "disk is full." You need to find out WHERE the space went, step by step, not just that it's full.

- `df -h` — shows how full each mounted filesystem is. Always the FIRST command in a disk incident, since it tells you WHICH filesystem is the problem (sometimes it's not even `/`).
- `du -h --max-depth=1 <path> | sort -rh` — shows the size of everything one level inside a folder, biggest first. You run this repeatedly, going one folder deeper each time, until you find the actual large file or folder. This is called "drilling down."
- `du -m` — same as above but forces output in plain megabytes instead of a mix of K/M/G, useful when you want exact numbers to compare.
- `2>/dev/null` — while drilling down, Linux will complain about folders you don't have permission to look into. This throws those error messages away so you only see the real data.
- `ls -lhS <path>` — sometimes `du` shows a folder is big, but doesn't make it obvious which SINGLE file inside is the culprit. This command lists files sorted by size (biggest first), which finds individual large files quickly.

---

## 2. Process Management (Finding and Killing Processes)

**The problem:** Something is using too much CPU or is stuck and needs to be stopped safely.

- `top` — shows a live, constantly refreshing list of everything running on the server, with CPU/memory usage. Press `q` to exit.
- `pgrep <name>` — finds the Process ID (PID) of something by its short name (like `sshd`). Best used for well-known service names.
- `pgrep -f "pattern"` — same idea, but searches the FULL command line instead of just the short name. Needed when the process name is generic (like `bash`) or longer than 15 characters (Linux only stores 15 characters for the short name). BE CAREFUL: this can accidentally match your OWN script if the pattern you're searching for also appears in your script's own arguments.
- `kill <PID>` — sends a signal called SIGTERM, which politely ASKS the process to shut down. Most well-behaved programs will listen to this. Always try this first.
- `kill -9 <PID>` — sends SIGKILL, which FORCES the process to stop immediately, with no chance to clean up after itself (like closing files or finishing a database write). Only use this if SIGTERM didn't work, since it can cause data issues.
- To kill something in one line without typing the PID yourself: `pgrep -f "x" | xargs kill -9` or `kill -9 $(pgrep -f "x")` — both find the PID and kill it in a single command, useful in scripts.

---

## 3. File Permissions

**The problem:** A script says "Permission denied" and won't run.

- `ls -l file` — shows a 10-character code like `-rwxr-xr-x`. Ignore the first character (file type). The remaining 9 are three groups of three: what the OWNER can do, what the GROUP can do, and what EVERYONE ELSE can do. Each group shows read (r), write (w), execute (x), or a dash if that permission is missing.
- "Permission denied" running a script has TWO different possible causes, and you need to check BOTH:
  1. **The execute bit is missing entirely** — nobody can run this file. Fix: `chmod +x file`
  2. **The execute bit exists, but not for YOU** — maybe the file is owned by someone else (like root), and you fall into the "everyone else" category which doesn't have execute permission. Fix: `chown yourusername:yourusername file` (only works if you already own it or use `sudo`)
- Never just run `chmod 777` to "make the error go away." This gives EVERYONE full read/write/execute access to the file, which is a real security risk, and it hides what the actual problem was instead of fixing it properly.

---

## 4. Hard Links, Soft Links, and Compression

**Hard link** (`ln file1 file2`): imagine two different name tags pointing to the exact same physical box of data on disk. If you delete one name tag, the box of data still exists as long as the other tag is still attached to it. Limitation: can't be used across different disks/filesystems, and can't be used on folders.

**Soft (symbolic) link** (`ln -s target linkname`): imagine a sticky note that just says "the real thing is over there." If you delete or move the real file, the sticky note becomes useless (a "dangling link"). Unlike hard links, soft links CAN point to folders and CAN point across different disks.

- `ls -li` — shows the "inode number" (a unique ID for the actual data on disk) next to each file. Two hard-linked files will show the SAME inode number, proving they're really the same data underneath.

**Compression:**
- `tar -czvf archive.tar.gz folder/` — bundles a folder into one compressed file. Breaking down the letters: `c`=create, `z`=use gzip compression, `v`=verbose (show progress), `f`=the filename you're creating.
- `tar -xzvf archive.tar.gz` — the reverse: extract/unpack a `.tar.gz` file.
- `gzip file` — compresses a single file, and by default REPLACES the original with the compressed version. `gunzip file.gz` reverses it.
- `zip -r archive.zip folder/` and `unzip archive.zip` — similar idea to tar, but more commonly understood by non-Linux users (like Windows), useful if you're sharing files outside a Linux environment.

---

## 5. Common Bash Syntax Rules That Trip People Up

- **No spaces around `=` when setting a variable.** `NAME=value` is correct. `NAME = value` is WRONG — bash thinks you're trying to run a command called NAME, not set a variable, and you'll get a confusing "command not found" error.
- **To READ a variable's value, you need a `$` in front of it.** Just writing `NAME` refers to the literal word "NAME," not what's stored inside it. You need `$NAME`.
- **If you misspell a variable name, bash does NOT give you an error.** It just treats the misspelled variable as if it were empty. This is dangerous because your script might run without complaining, but silently do nothing useful. Always double check spelling matches exactly.
- **When comparing numbers, brackets need spaces around them, and variables should be in quotes:** `[ "$VAR" -ge 10 ]` — notice the space after `[` and before `]`, and the quotes around `$VAR`. Missing these causes syntax errors.
- **`for x in $VAR` vs `for x in $VAR/*`** — if `$VAR` holds a folder path, looping over just `$VAR` treats the whole path as ONE single item (the loop only runs once!). Adding `/*` tells bash to expand it into the actual list of files inside that folder, so the loop runs once PER FILE, which is usually what you actually want.
- **Special variables:** `$0` is the script's own filename, `$1` `$2` etc. are the arguments someone passed in when running the script, `$$` is the current script's own Process ID, and `$*` represents all the arguments combined into one.
- **`shift`** — removes the first argument, so what used to be the second argument becomes the new "first" one. Useful when you want to process a variable number of arguments one at a time.
- **`local varname` inside a function** — keeps that variable trapped inside the function, so it doesn't accidentally overwrite a variable of the same name elsewhere in your script.
- **Heredoc: `cat << 'EOF' > file ... EOF`** — a quick way to write several lines of text directly into a file from within a script, without needing to open a text editor.

---

## 6. Writing Reliable Scripts

- **`$(command)`** — runs a command and captures whatever it prints, storing it in a variable.
- **`read VAR1 VAR2 <<< "$(command)"`** — splits a command's output into multiple separate variables at once, based on spaces.
- **Exit codes: 0, 1, 2** — this is a widely used convention (not just something we made up) where 0 means "everything is fine," 1 means "there's a warning, something's a bit off," and 2 means "critical, this needs attention now." Real monitoring tools understand and expect these numbers.
- **`set -e`** — placed near the top of a script, this tells bash "if ANY command fails, stop the whole script immediately instead of continuing on as if nothing happened." Important gotcha: sometimes a command "fails" for a totally normal reason (like `grep` finding zero matches), and `set -e` will kill your script anyway unless you add `|| true` after that specific command to say "it's okay if this one fails."
- **`trap cleanup EXIT`** — registers a function (here called `cleanup`) that will run automatically no matter HOW the script ends — whether it finishes normally, crashes partway through, or gets interrupted with Ctrl+C. This is different (and much safer) than just putting cleanup code at the very bottom of your script, because code at the bottom only runs if the script actually reaches that line — if something fails earlier, that cleanup code never runs at all.
- **`mktemp`** — creates a temporary file with a guaranteed unique name, safer than making up your own temp filename (which risks colliding with something else).
- **Math in bash only works with whole numbers, no decimals.** When calculating a percentage like `(used/total)*100`, always multiply FIRST, then divide — otherwise you lose accuracy because bash rounds down at every step.
- **`bash -x script.sh`** — runs your script in "debug trace mode," printing out literally every command it executes, with all variables already filled in with their real values. Extremely useful when a script's output doesn't match what you expected, and reading the code alone isn't revealing why.

---

## 7. Working With Files Safely

- **`mkdir -p`** — creates a folder, including any missing parent folders needed along the way, and does NOT complain if the folder already exists (unlike plain `mkdir`, which errors out if it does).
- **`cp source/* destination`** — if you're copying MULTIPLE files at once using a wildcard, the destination MUST already exist as a real folder. If it doesn't exist yet, `cp` gets confused: it might create a single file with that name instead of a folder, and each subsequent file you try to copy will just overwrite that file, silently destroying earlier data.
- **`mv` overwrites destination files with NO warning.** If you rename/move a file to a name that already exists, the old file is gone instantly, no confirmation asked. Always make sure destination names are unique (like adding a timestamp) if you're doing this repeatedly, such as in a script that might run more than once.
- **`find "$DIR" -name "pattern" -mtime "+$DAYS" -delete`** — a safe way to automatically clean up old files based on their age. Safer than piping results into `rm`, because `find`'s built-in `-delete` acts directly and predictably on exactly what matched.
- **`lsof <file>`** — "list open files." Before deleting a file you're not 100% sure about, this tells you if any currently-running program has that file open. If nothing shows up, that's one good signal (among others) that it's safe to delete.
- **Always double-check with `cat` or `ls -la` after editing a script, before running it again.** Don't just assume your edit saved correctly — verify it.

---

## 8. Cron Jobs (Scheduled Tasks)

**The problem:** A scheduled job seems to "just stop working," with cron showing no errors at all.

- By default, cron does not show you ANY output or errors from the jobs it runs — both normal messages and error messages just vanish into nothing.
- **`your-script.sh >> logfile.log 2>&1`** — added at the end of your crontab line, this captures BOTH normal output and error messages into a single log file, so you can actually see what happened. The order of `>> logfile 2>&1` matters — it must be written exactly in that sequence.
- Even with logging turned on, a script without proper error handling (`set -e`) might still print a false "Success!" message even when something inside it actually failed. Fixing VISIBILITY (being able to see what happened) and fixing HONESTY (the script correctly reporting whether it actually succeeded) are two separate problems — you need both fixed, not just one.

---

## 9. Text Processing (grep, awk, sed)

**The problem:** You have a huge, messy log file and need to answer specific questions about it, fast.

- **`grep "pattern" file`** — searches for lines containing a specific word or pattern. Add `-c` to just get a COUNT of matching lines, instead of the lines themselves.
- **`grep "A.*B" file`** — matches lines where A appears somewhere, followed eventually by B, later on the SAME line.
- **`awk '{print $3}'`** — log lines are usually split into columns by spaces. This extracts just column number 3 (or whichever number you specify) from every line.
- **`sort | uniq -c`** — a classic combo for counting how many times each unique value appears. IMPORTANT: you must `sort` FIRST, because `uniq` only collapses duplicate lines that are sitting right next to each other — it won't catch duplicates scattered throughout the file unless they're already grouped together by sorting.
- **`sed 's/find/replace/'`** — finds and replaces text. By default this does NOT change the original file, it just changes what gets printed/passed along — you'd need to add the `-i` flag if you actually wanted to edit the file directly.
- **The typical investigation pattern:** use `grep` to filter down to what you care about, then `awk` to pull out the specific piece of data you need, then `sort | uniq -c` to count and summarize it, and finally look at the numbers to draw a real conclusion.

---

## 10. Diagnosing a Slow Server

**The problem:** Someone says "the server feels slow," with no specific error to search for.

- **`uptime`** — shows the "load average," a rough measure of how busy the system has been over the last 1, 5, and 15 minutes. This tells you something is busy, but NOT what kind of busy.
- **`top`'s CPU line** (looks like `%Cpu(s): XX us, XX sy, XX id, XX wa`) is the real diagnostic tool:
  - If `id` (idle) is near ZERO and `us`/`sy` are high, the CPU itself is genuinely maxed out doing real work — a CPU-bound problem.
  - If `id` is actually HIGH (looks healthy) but `wa` (I/O wait) is elevated, that's misleading at first glance — it means the CPU has spare capacity, but processes are stuck WAITING on something slow, usually disk. This is a completely different problem than CPU being maxed out.
- **`free -m`** — check the SWAP row. If "used" swap is climbing, that's often the reason for the "high idle but elevated wait" pattern above — the system has run out of real memory (RAM) and is using the much slower disk as a substitute, which drags everything down.
- Interesting fact: once memory pressure goes away, swap usage does NOT automatically drop back to zero right away. Linux only moves data back out of swap when something actually needs it again — so seeing leftover swap usage after a spike is completely normal, not a sign of an ongoing problem.
- To set up swap space for testing: `fallocate` (creates the file) → `chmod 600` (locks down permissions, since swap can temporarily hold sensitive data from memory) → `mkswap` (formats it) → `swapon` (turns it on). To remove it safely: ALWAYS run `swapoff` BEFORE deleting the file — deleting an active swap file without disabling it first can cause real problems.

---

## 11. How to Investigate ANY Incident (The General Method)

This is the mindset that ties the entire module together, useful for literally any "something is wrong" situation:

1. **Confirm the actual symptom yourself** — don't just take someone's word for it, verify it directly (e.g., actually try to connect to the service, don't assume it's down just because someone said so).
2. **Check logs first** — often the fastest source of a direct clue, if logs exist and are readable.
3. **Check CPU and memory** (`top`, `free`) — quickly rule these in or out as a cause.
4. **Check disk space** (`df -h`, then drill down with `du`) — a surprisingly common, often overlooked cause of unrelated-seeming failures.
5. **Before fixing anything, verify it's actually safe to change** — check file ownership, whether anything has it open (`lsof`), and whether the timing lines up with when the problem started.
6. **After applying a fix, verify it actually worked** using real evidence — don't just trust that "no error appeared" means success.
7. **Write it up.** Every real, serious incident should end with a short written record of what happened and why — this is what the RCA format below is for.

---

## 12. RCA (Root Cause Analysis) Template

Use this structure every time you write up a real incident:

- **Problem** — a one-sentence description of what actually went wrong, from the user/customer's point of view.
- **Impact** — who or what was affected, and for how long.
- **Timeline** — the key moments, in order: when it started, when you noticed, what you checked, when you fixed it.
- **Root Cause** — the actual underlying reason it happened — not just the symptom you first noticed.
- **Resolution** — exactly what you did to fix it.
- **Preventive Action** — what you'd change going forward so this specific thing doesn't happen again.
- **Lessons Learned** — any broader, more general takeaway that applies beyond just this one incident.

---

## 13. Bugs That Kept Showing Up (Learn to Spot These Fast)

- Spaces accidentally left around `=` in a variable assignment
- Forgetting `mkdir -p` before copying multiple files into a folder that doesn't exist yet
- `mv` or `cp` silently overwriting an existing file with no warning
- A typo in a variable name that bash doesn't flag as an error, it just silently becomes empty
- Trying to `cp` several files into a destination that was never actually created as a real folder
- Trusting a script's own "Success!" message without independently double-checking that it actually did what it claimed

---

## 14. Bash Building Blocks We Touched Lightly (or Not At All) — Worth Knowing

These didn't get full hands-on practice this module, so treat them as "read about" rather than "drilled" — worth a quick practice pass before relying on them in an interview.

**Comparison operators, the full picture:**
- For NUMBERS: `-eq` (equal), `-ne` (not equal), `-gt` (greater than), `-ge` (greater or equal), `-lt` (less than), `-le` (less or equal)
- For TEXT/STRINGS: `=` (equal), `!=` (not equal) — these are DIFFERENT from the number operators above; mixing them up is a common bug (e.g., using `-eq` to compare two words instead of `=`)
- We mostly used `-ge` and `-lt` this module (numbers); string comparison with `=`/`!=` wasn't practiced much.

**`&&` and `||` as general control flow, not just one-off tricks:**
- `command1 && command2` — only runs command2 IF command1 succeeded (exited with code 0)
- `command1 || command2` — only runs command2 IF command1 FAILED (exited with non-zero)
- We used both of these (`[ "$STATUS" -lt 1 ] && STATUS=1` and `grep ... || true`), but as specific patterns rather than explaining the general idea: these are shortcuts for simple if/else logic on a single line.

**Background jobs and job control:**
- `command &` — runs a command in the background, giving you your terminal prompt back immediately (used throughout M01-P02, P08)
- `wait` — pauses the script/session until all background jobs finish (used once, in M01-P08)
- `jobs` — lists what background jobs are currently running in this session (not practiced)
- `fg` / `bg` — bring a background job to the foreground, or send a stopped job to the background (not practiced)

**`while` loops:**
- We used one (`while true; do sleep 1; done`) to simulate a stuck process, but never covered the more common real pattern: `while [ condition ]; do ... done` — repeats as long as a condition stays true, useful for things like "keep checking until a service comes back up" or "retry up to N times."

**`case` statements:**
- Not used at all this module. A cleaner alternative to long `if/elif/elif` chains, especially when a script's behavior depends on a single argument:
```bash
  case "$1" in
    start) echo "starting" ;;
    stop) echo "stopping" ;;
    *) echo "unknown option" ;;
  esac
```
- Common in real service-control scripts (`service.sh start|stop|restart`).

**`return` vs `exit` inside a function:**
- `exit N` — quits the ENTIRE script immediately, no matter where it's called from
- `return N` — only exits the CURRENT FUNCTION, handing back a status code to whoever called it; the rest of the script keeps running
- We used `exit` throughout (including inside functions like `cleanup()`), but never specifically needed or practiced `return` — worth knowing the distinction exists before writing scripts with more complex function chains.
