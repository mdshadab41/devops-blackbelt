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

## M02-P03 — First Merge Conflict

**What triggers a conflict:** Git auto-merges whenever changes DON'T
overlap on the same lines of the same file (proven in M02-P02). A
conflict only happens when both branches changed the SAME LINE(S) of
the SAME FILE in DIFFERENT ways - at that point Git can't algorithmically
decide which version is "correct," so it stops and asks a human.

**Conflict markers explained:**
<<<<<<< HEAD           <- start of YOUR current branch's version
(your branch's lines)
=======                 <- divider between the two versions
(incoming branch's lines)
>>>>>>> branch-name     <- end, labeled with the incoming branch's name

**Resolution steps:**
1. git merge <branch>          - triggers the conflict, Git pauses mid-merge
2. git status                  - shows "both modified" files
3. Open the file, manually edit out ALL markers, decide final content
   (options: keep mine / keep theirs / combine both / write something new)
4. git add <file>               - marks this file's conflict as resolved
5. git status                  - confirms "All conflicts fixed but still merging"
6. git commit (no -m)          - opens editor with pre-filled merge message,
   save+exit to finalize the merge commit

**Escape hatch:** git merge --abort - bails out completely, resets back
to exactly before the merge attempt. Good to know if a conflict resolution
goes wrong mid-way.

**Key insight:** conflicts are not repo corruption - Git is refusing to
guess at something only a human can judge (meaning/intent, not just text).

## M02-P04 — Production Incident: Committed to Wrong Branch

**Scenario:** Made commits directly on main by mistake instead of on a
feature branch. main must stay clean; commits must NOT be lost.

**The fix (2 steps):**
1. git branch <new-branch-name>
   - Creates a new branch pointer AT THE CURRENT COMMIT (wherever HEAD
     is right now). Captures the mistaken commits under a new label.
2. git reset --hard <last-good-commit-hash>
   - Moves the CURRENT branch's pointer (main) back to where it should
     be. Also updates working directory files to match.
   - Nothing is deleted - the commits still exist, just no longer
     "owned" by main. Proven by switching to the new branch and seeing
     the files reappear.

**Why reset --hard was SAFE here:** because another pointer
(feature-todo-tracking) was already referencing those commits BEFORE
main moved away from them. reset --hard is only dangerous when the
commits being reset past have NO other pointer (branch/tag) referencing
them - then they become unreachable (recoverable only via reflog,
covered in M02-P07).

**Golden rule:** before running reset --hard, always make sure the
commits you might lose are reachable from some other branch first.

**Core insight:** branches are just labels/pointers on commits. Fixing
"wrong branch" mistakes is just relabeling which pointer claims which
commits - not undoing or rewriting any actual work.

## M02-P04 — Exercise Detour: Reset on the WRONG branch (real mistake, real recovery)

**What happened:** Created a safety branch with `git switch -c <name>`,
which auto-switches onto it. Then ran `git reset --hard <hash>` while
standing on the SAFETY BRANCH (not main) - so the safety branch got
reset, not main. main still held the 3 mistake commits, untouched.

**Key lesson:** git reset --hard ALWAYS affects whichever branch HEAD
currently points to - never assume it acts on "the branch I meant."
Always check `git branch` (look for the *) right before running reset.

**The recovery (when a branch pointer gets lost entirely):**
git reflog
  - shows a full history of everywhere HEAD has pointed, including
    commits no branch currently references. Default retention ~90 days.
git branch <new-name> <commit-hash-from-reflog>
  - creates a branch pointing at that EXACT commit (not "wherever
    HEAD is now" - explicit hash instead), recovering the lost work.

**Big takeaway:** git reflog is Git's real safety net. Even a botched
reset/checkout/rebase rarely loses work permanently, AS LONG AS the
commit was ever committed or checked out locally. This is why Git is
very hard to truly lose work in, even when you mess up.

## M02-P05 — Undo Chaos: reset vs revert vs restore

**The three "undo" tools and when to use each:**

| Command              | Touches                          | Rewrites history? | Use when...                          |
|-----------------------|-----------------------------------|--------------------|----------------------------------------|
| git restore           | Working dir / staging only        | No (no commits)   | Undoing UNCOMMITTED changes            |
| git revert            | Adds a NEW commit                 | No (original stays visible) | Undoing something ALREADY PUSHED/shared |
| git reset --soft      | Moves branch pointer, keeps changes staged | Yes | Redoing/squashing OWN unpushed commits |
| git reset --hard      | Moves branch pointer + wipes working dir | Yes | Fully discarding unpushed commits (use safety-branch trick if unsure) |

**Why revert is safe for shared/pushed commits, reset is dangerous:**
Analogy: revert = "sending a correction message" in a group chat -
everyone still sees the original + the fix, no confusion.
reset (on shared history) = "deleting your original message" after
someone already read/replied to it - their reply now references
something that no longer exists on your side. This is how force-pushed
reset causes real teammate conflicts and lost/orphaned work.

**Golden rule:** reset is only safe on commits NOBODY ELSE has pulled
yet. Once something is pushed and others may have it, use revert instead.

**Proven live:** reverted a commit (content undone, original commit
stayed visible in log) -> then reset --soft past the revert commit
(revert commit vanished from history entirely, but its file changes
stayed staged, not lost) -> recommitted to get a clean final state.

## M02-P06 — Interactive Rebase (squashing messy commits)

**What it's for:** cleaning up your OWN local, unpushed commits before
opening a PR - turning "wip / fix typo / actually forgot this" into
one clean, reviewable commit.

**Command:** git rebase -i HEAD~N
  - opens editor with last N commits listed OLDEST-first (reverse of
    git log order)
  - each line: <action> <hash> <message>

**Key actions available:**
- pick    - keep this commit as-is
- squash (s) - merge this commit's changes INTO the previous commit,
  and combine their messages (prompts for a new combined message)
- fixup   - like squash, but silently discards this commit's message
- reword  - keep the commit's changes, but edit its message
- drop    - remove this commit entirely

**What happens:** first editor screen = pick your actions.
Second editor screen (if squashing) = write ONE final commit message
replacing all the squashed messages.

**Why squashed commits get a NEW hash:** a commit's hash is calculated
from its content (files changed + message + author + timestamp + PARENT
commit's hash). Squashing creates genuinely new content (new combined
diff, new message) so Git computes a fresh hash - it's not reusing an
old one. This also means every commit AFTER the rebased ones gets a
new hash too, since each commit's hash depends on its parent's hash -
one small rebase early in a chain reshapes the entire chain after it.

**Golden rule (same as reset):** only rebase commits nobody else has
pulled yet. Rebasing shared/pushed history creates the same
history-disagreement problem as reset --hard on shared commits.

## M02-P07 — Production Incident: Teammate Force-Pushed

**Scenario:** Teammate ran `git reset --hard` + `git push --force` on a
shared branch, wiping a commit off the remote that you had already pushed.

**How to detect it:** git fetch origin, then compare:
git log --oneline origin/main   vs   git log --oneline main
If your LOCAL branch still has commits that origin/main doesn't -
those commits are safe, they just got removed from the REMOTE, not
from your machine. `git fetch` (unlike pull) never touches your local
branch, only updates what you know about the remote.

**Fetch output tells you directly:**
"+ <old>...<new> main -> origin/main (forced update)" - the
"(forced update)" tag is Git's explicit warning that the remote's
history was rewritten, not just fast-forwarded normally.

**The fix (if your local branch still has the commit):**
Just `git push origin main` again - normal push, no --force needed,
because your commit sits cleanly on top of the remote's current tip.
Git only checks "does this continue from the remote's CURRENT state" -
it has no memory of HOW the remote got there (normal push vs force-push).

**Harder variant (if YOUR local branch also lost the commit, e.g. you
pulled the bad history before checking):** use `git reflog` (from
M02-P04) to find the lost commit's hash, then `git branch <name> <hash>`
to recreate a branch pointing at it, then push that branch/commit back.

**Real-world prevention:** branch protection rules (M02-P13) can block
force-pushes to shared branches entirely - the actual production fix
for this class of incident is to prevent it, not just recover from it.

## M02-P08 — Cherry-pick a Hotfix

**Scenario:** A fix exists on `dev`, but production runs `main`. dev
also has unfinished/unrelated commits that must NOT come to main.
Need exactly one commit, not the whole branch.

**Command:** git cherry-pick <commit-hash>
  - Applies ONLY that commit's changes onto your current branch
  - Creates a NEW commit (new hash - same reason as squash in M02-P06:
    hash depends on content + parent, and parent is different here)
  - Original commit message is carried over automatically

**Cherry-pick vs merge - the real distinction:**
- merge <branch>   -> brings in the branch's ENTIRE history (every
  commit not already on your branch)
- cherry-pick <hash> -> brings in exactly ONE hand-picked commit,
  ignoring everything else on that branch

**Real-world use cases:** hotfixes (this scenario), backporting a fix
to an older release branch, salvaging one good commit from an
otherwise messy/abandoned branch.

**Analogy:** merge = photocopying someone's entire notebook and adding
it to yours. cherry-pick = copying just ONE page you actually need.
