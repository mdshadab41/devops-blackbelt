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

## M02-P09 — Detached HEAD State

**Normal state:** HEAD -> branch name -> commit (e.g. HEAD -> main -> 4be6630)
**Detached state:** HEAD -> commit DIRECTLY, no branch involved

**How to enter it:** git checkout <commit-hash> (or old-style checkout
of a specific commit instead of a branch name)

**Git's own warning is genuinely useful** - it tells you exactly what
state you're in and gives you the fix command in advance:
"git switch -c <new-branch-name>" to save any work before leaving.

**The risk:** commits made while detached are NOT tracked by any
branch. If you switch to a branch afterward, Git proactively warns:
"you are leaving N commit(s) behind, not connected to any of your
branches" - and gives you the exact rescue command:
git branch <new-branch-name> <commit-hash>

**Why it's not actually dangerous (if you know this):** the commit
still exists in Git's storage even after switching away - same safety
net as M02-P04/P07 (findable via reflog even if you forget to branch
it immediately). But best practice: branch it right away if you want
to keep it, don't rely on reflog as the primary plan.

**When detached HEAD is useful/safe:** just LOOKING at old code
(inspecting a past commit, comparing against a bug report) without
committing anything - completely safe, just switch back to a branch
when done looking.

## M02-P10 — GitHub PR Workflow & Merge Strategies

**PR is a GitHub feature, not a Git concept.** Git only knows branches
and commits; GitHub adds the review/discussion/approval layer on top.

**Real workflow used:**
1. git switch -c <branch-name>          - create feature branch
2. commit changes locally
3. git push -u origin <branch-name>     - push branch, GitHub gives
   a direct PR creation link in the output
4. Open PR on GitHub (title + description)
5. Review "Files changed" tab (GitHub's visual git diff)
6. Choose a merge strategy, merge
7. git pull origin main                 - sync merged result locally
8. Delete branch: git branch -d <name> (local) +
   git push origin --delete <name> (remote) - full cleanup

**Three merge strategies (GitHub PR merge dropdown):**

| Strategy | Individual commits kept? | Merge commit? | History shape |
|----------|---------------------------|----------------|----------------|
| Create a merge commit | Yes, all | Yes | Branches visible in graph |
| Squash and merge | No - combined into 1 | Yes (the squash itself) | Clean, 1 commit per PR |
| Rebase and merge | Yes, all | No | Straight line, no branch shape |

**Why squash and merge is common:** guarantees main's history stays
clean (1 commit per feature) regardless of how messy the branch's
WIP commits were - no need to manually rebase first (M02-P06).

**Trade-off:** squashing loses fine-grained commit-by-commit history
within a feature - matters for git bisect (M02-P14), which benefits
from smaller, more granular commits to narrow down a regression.

**GitHub-specific touch:** squashed commit message auto-includes the
PR number, e.g. "docs: add CONTRIBUTING.md (#1)" - links back to the
full PR discussion/description for future reference.

## M02-P11 — Rebase Conflicts (Broken PR scenario)

**Setup:** branch and main both edited the same line differently.
Instead of merging, tried `git rebase main` to replay branch commits
on top of the new main - hit a conflict mid-replay.

**Key difference from merge conflicts:**
- Finishing a MERGE conflict: git add + git commit (creates a NEW
  merge commit with two parents)
- Finishing a REBASE conflict: git add + git rebase --continue
  (rewrites the EXISTING commit in place, no new commit created)

**During rebase, HEAD means something different than usual:**
HEAD = the base you're rebasing ONTO (e.g. main), not "your branch."
Conflict markers reflect this - <<<<<<< HEAD shows main's version,
not your branch's version like in a normal merge conflict.

**Rebase's 3 recovery options (shown directly in the error message):**
- git rebase --continue  - after fixing conflict, keep replaying
  remaining commits
- git rebase --skip      - abandon THIS commit entirely, move to next
- git rebase --abort     - bail out completely, restore pre-rebase state

**Result:** rebase produces a clean, single-line history (commit
rewritten to sit directly on new base) - NO merge commit, unlike
resolving the same conflict via merge. Same benefit as GitHub's
"Rebase and merge" PR option (M02-P10), done manually before opening
the PR.

**Simple analogy:** merge = keep both paths + add a connector commit.
rebase = erase the fork, pretend your commits were always on the new base.

## M02-P12 — Production Incident: Secrets Committed by Mistake

**Why `git rm <secret-file>` + commit does NOT fix this:**
Git preserves every past commit's full snapshot forever. Deleting a
file only changes the CURRENT snapshot going forward - the old commit
containing the secret is still fully intact and readable via
`git show <old-commit>:<filename>`. This is the #1 real-world mistake
that causes actual credential leaks even after "fixing" it.

**The correct tool: git-filter-repo** (modern replacement for the
deprecated/slower git filter-branch)
Install: pip install git-filter-repo --break-system-packages
  - installs to ~/.local/bin - may need to add to PATH:
    export PATH="$HOME/.local/bin:$PATH"  (add to ~/.bashrc to persist)

**Command:** git filter-repo --path <file> --invert-paths --force
- --path <file>       - target this specific file
- --invert-paths      - REMOVE this path from all history (without
  this flag, filter-repo does the OPPOSITE: keeps ONLY this path)
- --force             - override the safety check that normally
  requires running on a fresh clone

**What it actually does:** rewrites EVERY commit in history, rebuilding
each one as if the file never existed. If a commit's entire content was
just that file, the commit is removed from history ENTIRELY (not just
edited). All commit hashes change (same cascading-hash rule as M02-P06).

**Automatic safety feature:** filter-repo removes the 'origin' remote
after rewriting - forces you to deliberately reconnect and confirm
before pushing rewritten history anywhere, since force-pushing
history that others may have already pulled causes the same
"history disagreement" problem covered in M02-P05/P07.

**CRITICAL - cleaning history is NOT enough by itself:**
1. Rotate/invalidate the actual credential FIRST, immediately, the
   moment you realize it was committed/pushed - assume it's
   compromised regardless of how fast you clean history after.
2. Clean history with filter-repo (removes FUTURE exposure risk)
3. Force-push the rewritten history if it was already pushed
4. Still doesn't undo exposure that already happened - clones, forks,
   GitHub's own caches, or anyone who already saw it may still have it.

**One-line rule:** deleting a secret's file only stops it from being
in NEW commits. The secret is still permanently readable in OLD
commits until you rewrite history with a tool like filter-repo -
and even then, rotating the actual credential is the real fix.

## M02-P13 — Branch Protection Rules (Manager Task)

**Setup:** GitHub repo Settings -> Branches -> Add branch protection rule
Branch name pattern: main
Enforcement status: MUST be set to "Active" (can silently be
"Inactive" by default - easy to miss, rule does nothing until active)

**Key protections enabled and why:**
- Require a pull request before merging -> blocks ALL direct pushes
  to main, even from repo owner/admins. Prevents M02-P04's entire
  scenario (accidental direct commit to main) structurally.
- Restrict/disallow force pushes -> blocks git push --force to main
  through GitHub entirely. Prevents M02-P07's entire scenario
  (teammate force-pushing over shared history) structurally.
- Restrict deletions -> prevents main branch itself from being
  accidentally deleted.
- "Do not allow bypassing" -> ensures even repo admins can't quietly
  skip these rules, or the protection is meaningless.

**Solo-dev consideration:** left "Require approvals" at 0, since a
required-approval count >=1 with no other collaborators would lock
me out of merging my own PRs. Revisit if this becomes a team repo.

**Proven live:** attempted a direct push to main after enabling ->
GitHub rejected it: "remote rejected... push declined due to
repository rule violations." Had to redo the fix through a proper
branch + PR (reused the M02-P04 wrong-branch recovery pattern:
branch the commit, reset main back, push branch, open PR, merge).

**Core lesson - prevention vs recovery:**
Everything through M02-P12 was REACTIVE - an incident happens, you
need skill to recover from it correctly. Branch protection is
PROACTIVE - it changes the system so the incident structurally
cannot happen at all, regardless of anyone's skill or mistake.
This is the mindset shift a "Manager Task" problem is really testing.

## M02-P14 — Git Bisect: Binary-Search a Regression

**The problem:** a bug exists NOW, but you don't know which of many
commits introduced it. Checking each commit one-by-one is slow
(N tests for N commits).

**The fix - binary search over commit history:**
git bisect start
git bisect bad HEAD           - mark current/latest as confirmed BROKEN
git bisect good <old-commit>  - mark a known-working old commit as GOOD
  - Git checks out the MIDPOINT commit between good and bad for you

Then repeat for each checkout Git gives you:
  - test the code manually
  - git bisect good   (if bug NOT present here)
  - git bisect bad    (if bug IS present here)
Git narrows the range by HALF each time, until it reports:
  "<hash> is the first bad commit"

git bisect reset   - IMPORTANT final step: exits bisect mode, returns
  you to your original branch (not left in detached HEAD)

**Why it's fast:** each good/bad answer eliminates HALF the remaining
candidate commits - not just the one tested. This is why it takes
roughly log2(N) tests instead of N tests:
- 6 commits  -> ~2-3 tests
- 100 commits -> ~7 tests
- 1000 commits -> ~10 tests
The bigger the commit range, the more dramatic the time savings vs
checking commits one at a time.

**Key nuance:** "good" doesn't mean "no bugs at all" - it means "the
SPECIFIC bug I'm hunting is not present here." Proven live: a commit
where the buggy function didn't even exist yet still correctly counts
as "good" for this bisect.

**Real-world value:** essential for finding exactly which commit
introduced a regression across a large history, especially useful in
combination with automated tests (git bisect run <test-script> can
even automate the good/bad testing itself).

## M02-P16 — Timed Interview Challenge (3 problems, live)

**Problem 1 — Discard an unpushed bad commit**
Tool: git reset --hard HEAD~1
Why safe: commit was never pushed, nobody else could have pulled it -
zero risk of history disagreement (M02-P05/P07 rule).

**Problem 2 — Remove a MIDDLE commit from already-shared history**
Tool: git revert <commit-hash>
Why revert (not reset): reset can only cut commits from the TIP
backward - structurally cannot remove one commit from the middle
while preserving commits that came after it. Revert has no such
limitation since it doesn't move pointers, it calculates an undo and
applies it as a new commit, regardless of position in history.
Also required for shared history safety (same as Problem 1's inverse
condition - this one WAS already pushed/pulled by a teammate).

**Problem 3 — Rebase onto updated main, keep straight-line history**
Tool: git rebase main
Key skill: CHECKED FIRST whether a conflict would actually happen,
instead of assuming - confirmed the two branches never touched the
same file, so rebase completed with zero conflicts. Result: straight
line history, no merge commit, exactly as required.

**Overall lesson:** correct tool choice depends on answering two
questions every time - (1) has this commit been shared with anyone
else? and (2) do I need to target the tip, or somewhere in the
middle of history? Reset = tip only, unshared only. Revert = anywhere
in history, safe even if shared. Rebase = replays commits onto a new
base, clean history, safe only if the branch being rebased is not
yet shared/pushed.
