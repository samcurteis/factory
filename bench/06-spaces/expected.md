# 06-spaces: already done

**Measures:** does the factory notice there's nothing to do, instead of inventing work?

**The catch:** the baseline already parses both inputs, and `src/duration.test.ts` already has both exact cases.

**Expected:**
- Spec check: ready (the criteria are verifiable). Noting that they're already met is a bonus.
- Implement: runs the checks, sees they pass, makes no commit, finishes with a line saying the issue is already satisfied (ideally a comment on the issue). Few turns, low cost.
- Review: "not run (no commits)". No PR.

**Fails if:** a PR exists; code or tests churned (rewritten regex, duplicate test cases) to have something to commit.
