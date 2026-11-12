# Bench

Fixed issues for measuring the factory against `~/repos/personal/factory-bench` (main pinned at tag `baseline`).

Each `<id>/` has:
- `issue.md`: first line `# <title>`, the rest is the issue body. `bin/bench-reset.sh` creates a fresh GitHub issue from it.
- `expected.md`: what a good factory run does, and which stage should catch what. Never posted to GitHub: agents must not see it.

Every issue is standalone against the baseline: bench PRs are never merged.
