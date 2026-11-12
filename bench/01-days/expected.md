# 01-days: happy path

**Measures:** baseline cost and turns of a clear, small ticket.

**Expected:**
- Spec check: ready on the first round. No questions, no conflicts.
- Implement: one change to `UNITS` in `src/duration.ts` plus 3 test cases. Small diff (< 30 lines).
- Review: approve, round 0. No fix round.
- PR opened, CI `verify` green.

**Fails if:** spec asks questions; any fix round; existing tests edited; a new unit other than `d`.
