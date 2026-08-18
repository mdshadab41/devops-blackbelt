# RCA — M02-P15: Discount Calculation Bug

**Problem:**
calculate_discount() in inventory.py was producing wildly incorrect
(massively negative) prices instead of applying a correct percentage
discount.

**Impact:**
Any code relying on calculate_discount() would return incorrect
pricing - e.g., a $100 item with a 10% discount returned -$99,900
instead of $90. In a real production system, this would mean
customers seeing broken prices, or worse, orders being processed
incorrectly without anyone noticing.

**Timeline:**
- Bug introduced in commit 3cb50ff, "refactor: simplify discount calculation"
- Two further commits were added on top before the bug was discovered,
  meaning it sat undetected through 2 additional changes
- Discovered when the function was manually tested and produced an
  obviously wrong result

**Root Cause:**
The refactor commit changed `discount_percent / 100` to
`discount_percent * 100` - likely a typo or misunderstanding of the
math while "simplifying" the calculation. Converting a percentage to
a decimal requires DIVIDING by 100; multiplying instead inflated the
discount amount by a factor of 10,000, producing a deeply negative
final price. Since the function didn't crash or throw an error - it
just returned a wrong number - the bug went unnoticed without a test
verifying actual output.

**Resolution:**
Used git bisect to narrow down the exact breaking commit from a
5-commit range in 3 tests. Confirmed the exact cause via git show.
Fixed using git revert (not a manual edit or history rewrite) since
the bad commit was already on the shared main branch - revert
preserves history honestly and avoids the risk of rewriting commits
others may have already pulled. Verified the fix by re-running the
function and confirming correct output before merging.

**Preventive Action:**
- Add an automated unit test for calculate_discount() checking a known
  input/output pair (e.g. calculate_discount(100, 10) == 90) - this
  class of "wrong number, no crash" bug is exactly what tests catch
  and manual review often misses
- Treat "refactor" commits with extra scrutiny in code review, since
  they're meant to change HOW code works without changing WHAT it
  does - any refactor that changes actual behavior is a red flag
- Branch protection (M02-P13) wouldn't have prevented this specific
  bug (it was a legitimate-looking commit), but it does ensure any
  fix goes through a proper PR rather than a rushed direct push to main

**Lessons Learned:**
git bisect turns "which of N commits broke this" from a slow, manual
guessing process into a fast, systematic one - genuinely one of the
most valuable debugging tools in this module. Also reinforced that
revert (not rewriting history) is the correct fix for a bug already
on a shared branch, even under time pressure.
