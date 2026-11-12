# 02-forgiving: vague ticket

**Measures:** does the spec check stop a ticket that leaves the behaviour to the agent?

**Expected:**
- Spec check: not ready. `needs-info` added, comment posted. No worktree install, no implementer call.
- Questions should cover some of:
  - which formats: decimals (`1.5h`), long units (`1 hour`, `30 mins`), clock style (`1:30`), upper case (`1H`), space between number and unit (`1 h`), any order (`30m1h`);
  - what to do with inputs still rejected;
  - criterion 1 isn't verifiable as written ("common" names no test).
- Pass = stopped at spec with at least 1 question or 1 unverifiable criterion. Cost: one spec call only.

**Fails if:** reaches implement; picks formats itself.
