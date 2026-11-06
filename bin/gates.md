# Factory gates: what an implementer run can and can't do

- Runs headless, unattended, in a fresh git worktree from origin/main, on branch factory/issue-N. No human to ask mid-run.
- Bash allowlist, nothing else: any `pnpm` script; `gh issue view`; `gh issue comment` and add `needs-info` on its own issue; `gh pr create`; `gh run watch/view/list`; `gh pr checks`; `git status/diff/log/add/rm/commit`; `git push` of its own branch. No `git revert/reset/checkout/rebase`, no `curl`, no `gh api`, no other labels, no repo or CI settings.
- Read-only commands (`ls`, `grep`, `git show`, `git grep`, `git ls-files`) are always allowed.
- One plain command per Bash call: no `&&`, `;`, redirects or multi-line commands.
- File tools can't write outside the worktree. Shell commands run in an OS sandbox with no network (except `gh`, `git push`, and the e2e/verify:all commands).
- Stop hook: on factory/issue-N it can't finish while `pnpm verify:all` (verify + Playwright e2e) fails, unless the issue has the `needs-info` label.
- `main` requires the `verify` CI check. Humans merge.
- Tests never call live intervals.icu. No API key is available. Nobody looks at the screen: anything "checked by eye" isn't checked.
