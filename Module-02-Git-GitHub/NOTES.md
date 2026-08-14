# Module 02 — Git & GitHub — Notes

## Core Definitions (reference)

**Git vs GitHub:**
- Git = the version control TOOL. Works 100% offline. Tracks snapshots
  of your code over time, on your own machine.
- GitHub = a HOSTING SERVICE + collaboration layer built on top of Git.
  Adds: remote backup of your repo, Pull Requests, code review, Issues,
  GitHub Actions (CI/CD), team access control. Needs internet.
- Analogy: Git is like a diary you keep locally. GitHub is like
  publishing/sharing that diary online so others can read, comment,
  and propose edits to it.

**The Three Trees (where a file "lives"):**
1. Working Directory - the actual files on disk, exactly as you see
   them in a text editor / `ls`. Git watches this area but changes
   here are NOT tracked until staged.
2. Staging Area (aka "Index") - a holding area for a SNAPSHOT of a
   file, built via `git add`. This is what goes into the NEXT commit.
   Not permanent - can be wiped/changed anytime before committing.
3. Repository - the permanent, committed history, stored inside
   .git/. Created via `git commit`. This is what `git log` shows you.

**Flow:** Working Directory --(git add)--> Staging Area --(git commit)--> Repository

---

## M02-P01 — Git Fundamentals (three-tree model)

**Concept:** Git tracks files across three areas:
- Working Directory (files on disk)
- Staging Area / Index (git add — snapshot staged for next commit)
- Repository (git commit — permanent snapshot in history)

**File states observed:**
Untracked -> Staged -> Committed -> Modified -> Staged -> Committed (loop)

**Key commands:**
- git init            - create repo, sets up .git/
- git status           - shows which of the 3 states each file is in
- git add <file>       - working dir -> staging area
- git commit -m "msg"  - staging area -> repository (permanent snapshot)
- git log / git log --oneline - view commit history

**Key gotcha:** commit only includes what's STAGED, not what's currently
on disk. Edits made after `git add` but before `git commit` are NOT
included unless re-staged.

**Housekeeping:** set init.defaultBranch to main globally to match
GitHub convention (avoids master/main mismatch later).

---

## M02-P01 — Exercises (staging area deep-dive)

**Key insight:** Staging Area holds a SNAPSHOT, not a live link. If you
edit a file after `git add`, the new edit is separate until you re-`add`.
This is why a file can show in BOTH "Changes to be committed" AND
"Changes not staged" simultaneously.

**Commands learned:**
- git show <hash>              - view exact diff introduced by one commit
- git restore --staged <file>  - unstage only (working dir edit KEPT)
- git restore --worktree <file> - discard working dir edit only (staged KEPT)
- git restore --staged --worktree <file> - discard BOTH, full reset to HEAD
- git checkout -- <file>       - legacy (pre-2.23) equivalent of the above

**Gotcha:** Git refs are case-sensitive. HEAD (caps) is a real pointer;
head (lowercase) is not recognized -> "ambiguous argument" error.

**diff format reminder:** '+' = line added, '-' = line removed,
@@ -0,0 +1,2 @@ = hunk header showing line range affected.

## M02-P02 — Branching Basics

**Concept:** A branch is just a POINTER to a commit, not a copy of files.
Creating a branch is instant regardless of repo size because of this.

**Commands learned:**
- git branch <name>     - create a new branch pointer (does NOT switch to it)
- git switch <name>     - move HEAD to a different branch (modern command, 2.23+)
- git branch            - list branches, * marks current one
- git merge <name>      - bring another branch's commits into current branch
- git branch -d <name>  - delete a branch (safe: refuses if unmerged work exists)
- git log --oneline --all --graph  - visualize branch history/divergence

**Fast-forward merge:** happens when the target branch (e.g. main) has NOT
moved since the feature branch was created. Git just slides main's pointer
forward to match - no new commit, no combining, no conflict possible.

**Real merge (contrast, covered next in M02-P03):** happens when BOTH
branches have new commits since diverging. Git creates a new merge commit
with two parents to combine both histories. This is where conflicts can occur.

**Simple analogy:** Fast-forward = other branch stood still, so just catch up.
Real merge = both branches moved on different paths, so stitch them together.

## M02-P02 — Live Proof: Non-fast-forward merge with ZERO conflict

**Setup:** Created feature-changelog branch, committed CHANGELOG.md on it.
Meanwhile, committed LICENSE.md directly on main (different file, no overlap).

**Result of merge:** Git created a MERGE COMMIT (two parents), NOT a
fast-forward — even though the two files never touched the same lines
and Git needed zero help resolving anything.

**Key lesson:** Fast-forward vs real merge depends ONLY on whether the
target branch (main) moved since divergence. Conflict is a SEPARATE
question - it only determines whether Git needs manual help combining
overlapping changes. A conflict-free real merge still produces a
merge commit; only a completely untouched target branch fast-forwards.

**Commands used in this exercise:**
- git switch -c <name>        - create + switch to new branch in one step
- git branch -m <old> <new>   - rename a branch (fixes typos safely)
- git log branchA..branchB    - show commits on branchB not in branchA
- git log --oneline --all --graph  - visualize all branches + merge commits
