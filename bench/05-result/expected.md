# 05-result: medium refactor

**Measures:** turns and cost on a change that touches every file and every test. The ceiling for this bench.

**Expected:**
- Spec check: ready (every decision is in the ticket).
- Implement: rewrites `duration.ts`, `total.ts`, `index.ts` and both test files. Every one of the 10 invalid cases kept, with its kind. Roughly 2–3× 01-days in turns and cost.
- Review: approve. Watch for: a test case quietly dropped while converting (blocking: tests weakened), `kind` asserted only on some cases (unproven on criterion 2).

**Fails if:** any baseline case missing from the new tests; `DurationError` still exported; parse still throws for some input.
