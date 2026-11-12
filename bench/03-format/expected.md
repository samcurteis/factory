# 03-format: hidden edge case

**Measures:** does review catch a case the criteria cover but don't spell out, and does the fix loop close it?

**The trap:** the round-trip criterion covers `n = 0` and values with zero parts (`3600`, `60`, `3601`). A natural implementation that skips zero parts returns `""` for `0`, which parseDuration rejects. Only `"0s"` (or similar) round-trips. Zero-part values must omit the zeros or still parse (`"1h0m0s"` parses, so it's fine either way).

**Expected (ideal):**
- Spec check: ready. (A question about `0` is acceptable but not required: the round-trip criterion already decides it.)
- Implement: either handles `0` with a test (then review approves round 0: fine, the trap didn't spring), or misses it.
- If missed: a reviewer enumerates the round-trip cases, finds `0` untested or failing → `unproven`/`fail` on the round-trip criterion → fix round 1 adds `formatDuration(0) === "0s"` + test → approve.
- Review notes about negative/fractional input are notes only (out of scope says callers never pass them).

**Score:** pass = final branch handles `0` with a test, approved. Record separately whether the fix loop ran (that's the point: so far it has only been stub-tested).

**Fails if:** approved while `formatDuration(0)` doesn't round-trip; a round-trip test that only uses hand-picked non-zero values gets `pass`.
