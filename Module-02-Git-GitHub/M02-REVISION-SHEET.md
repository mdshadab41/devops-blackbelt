# Module 02 Revision Sheet — Git & GitHub

## Quick Cheat Sheet (read this first, night before an interview)

| Need to... | Use |
|---|---|
| Undo an uncommitted change | git restore <file> |
| Undo unpushed commits (nobody has them) | git reset --hard <commit> |
| Undo a commit already pushed/shared | git revert <commit> |
| Remove a commit from the MIDDLE of history | git revert (reset can't reach the middle) |
| Clean up my own messy unshared commits | git rebase -i HEAD~N |
| Bring ONE commit from another branch | git cherry-pick <commit> |
| Find which commit broke something | git bisect |
| Find who last touched a specific line | git blame <file> |
| Recover "lost" work | git reflog |
| Stop Git from tracking junk files | .gitignore |
| Prevent incidents instead of recovering | Branch protection rules |

The single most important question before using reset/revert/rebase:
has this commit been pushed and possibly pulled by someone else?
Yes -> never rewrite it, use revert. No -> reset/rebase are safe.

---

## 1. The Big Picture: What Git Actually Is

Git tracks files across three areas:
- Working Directory - the actual files you see and edit
- Staging Area (Index) - snapshot via git add, waiting for next commit
- Repository - permanent history, saved via git commit

Flow: Working Directory -> (git add) -> Staging Area -> (git commit) -> Repository

Gotcha: git commit only saves what's staged, not what's on screen.
Edit after add but before commit, and it's left out unless re-added.

Git vs GitHub: Git = offline tool tracking history. GitHub = website
hosting history online, adding PRs, code review, team features.

---

## 2. Ignoring Files Git Shouldn't Track - .gitignore

echo "__pycache__/" >> .gitignore
echo "*.pyc" >> .gitignore
git add .gitignore
git commit -m "chore: add gitignore for python cache files"

Why it matters: without it, build artifacts and temp files clutter
git status, tempting accidental commits of things that shouldn't be shared.

---

## 3. Branches - What They Really Are

A branch is just a label pointing at one commit - not a copy of the project.

- git branch <name>      - creates a label, doesn't switch to it
- git switch <name>      - moves you onto a branch
- git switch -c <name>   - create + switch in one step
- git branch -d <name>   - delete (safe, refuses if unmerged work exists)
- git branch -m <old> <new> - rename
- git log --oneline --all --graph - visualize all branches

---

## 4. Merging - Fast-Forward vs Real Merge

Fast-forward: target branch hasn't moved since split -> pointer slides
forward, no new commit.

Real merge: BOTH branches have new commits since split -> two-parent
merge commit created, REGARDLESS of whether changes actually conflict.

Key rule: fast-forward vs real merge depends only on whether the
target moved. Conflict is a separate question entirely.

---

## 5. Merge Conflicts

Happens only when both branches changed the SAME lines of the SAME
file differently.

<<<<<<< HEAD
(your current branch's version)
=======
(the incoming branch's version)
>>>>>>> branch-name

Resolve: edit out all markers, decide final content -> git add <file>
-> git commit (merge) or git rebase --continue (rebase - different
command, no new commit created).

Escape hatch: git merge --abort / git rebase --abort

---

## 6. Undoing Things - restore / reset / revert

| Situation | Tool |
|---|---|
| Uncommitted change, discard it | git restore <file> |
| Unpushed commits, only I have them | git reset (--soft keeps staged, --hard discards) |
| Already-pushed, others may have it | git revert <commit> - adds NEW corrective commit |

Analogy: revert = sending a correction in a group chat, everyone sees
both messages. reset (on shared history) = deleting your original
message after someone replied - chaos.

---

## 7. Interactive Rebase - Cleaning Up Before a PR

git rebase -i HEAD~N
- pick    - keep as-is
- squash  - merge into previous commit, combined message
- reword  - keep changes, edit message only
- drop    - remove entirely

Why squashed commits get new hashes: hash = content + message + parent
hash. New content/message = new hash. Cascades to every commit after.

Golden rule: only rebase unpushed commits - same danger as reset --hard.

---

## 8. Cherry-pick - One Commit, Not the Whole Branch

git cherry-pick <hash> - copies ONE commit's changes onto current branch.

vs merge: merge brings ENTIRE branch history. cherry-pick brings ONE
hand-picked commit. Used for hotfixes and backporting.

---

## 9. Detached HEAD

Normal: HEAD -> branch -> commit. Detached: HEAD -> commit directly,
no branch (via git checkout <hash>).

Safe for looking around. Risky only if you commit while detached
without branching - use git switch -c <name> to save the work.

---

## 10. Recovering Lost Work - git reflog

git reflog - shows everywhere HEAD has pointed, including unreachable
commits (~90 day retention default).

git branch <new-name> <hash-from-reflog> - rescues it.

Almost nothing is permanently lost once committed.

---

## 11. Finding Who Changed a Line - git blame

Complementary to bisect. bisect finds which COMMIT broke a BEHAVIOR.
blame finds who last changed a specific LINE.

git blame <filename>

Suspicious line known -> blame. Broken but cause unknown -> bisect.

---

## 12. Force-Pushed History Recovery

git fetch = read-only, never touches local branch.
git pull = fetch + merge, CAN affect local work.

If a teammate force-pushes over shared history:
1. git fetch origin (safe) -> compare origin/main vs main
2. Local branch still has it -> just push again, normal push
3. Local also lost it -> use reflog to recover

Real prevention: branch protection can block force-pushes entirely.

---

## 13. GitHub Pull Requests

Workflow: git switch -c <branch> -> commit -> git push -u origin
<branch> -> open PR -> review "Files changed" tab -> merge -> git
pull origin main -> delete branch (local + remote).

Three merge strategies:
| Strategy | Effect |
|---|---|
| Create a merge commit | All commits + new 2-parent merge commit |
| Squash and merge | All commits combined into ONE clean commit |
| Rebase and merge | All commits kept, no merge commit, straight line |

Real lesson learned: a branch was deleted right after opening a PR,
before confirming the merge completed on GitHub - left a commit
temporarily homeless, recovered via reflog rescue. ALWAYS verify a
merge genuinely completed (GitHub UI or git log) BEFORE cleanup.

---

## 14. Branch Protection - Prevention Over Recovery

- Require PR before merging -> blocks direct pushes to main
- Disallow force pushes -> blocks force-push to main
- Restrict deletions -> prevents main from being deleted

Current status on devops-blackbelt: protection was set up, tested,
proven working - then deliberately REMOVED (solo-repo preference).
Direct pushes to main currently allowed again. Check GitHub Settings
-> Branches directly if unsure of current state.

---

## 15. Finding a Bug's Origin - git bisect

git bisect start
git bisect bad HEAD
git bisect good <known-working-commit>

Git checks out midpoint. Test it, answer good/bad. Repeat until Git
reports first bad commit. ALWAYS finish with git bisect reset.

Why fast: each answer eliminates HALF remaining commits - log2(N)
tests instead of N. 100 commits = ~7 tests, not 100.

---

## 16. Quick Decision Guide

Q1: Has this commit been pushed/pulled by someone else?
No -> reset is safe. Yes -> use revert.

Q2: Tip of history, or the middle?
Tip -> reset works. Middle, keep later commits -> only revert reaches it.

Other lookups:
- One commit from another branch -> cherry-pick
- Clean up unshared messy commits -> rebase -i
- Don't know which commit broke something -> bisect
- Know the line, want its history -> blame
- Think work is lost -> check reflog first
