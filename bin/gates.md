# Factory gates: what an implementer run can and can't do

- Runs headless, unattended, in a fresh git worktree from origin/main, on branch factory/issue-N. No human to ask mid-run.
- Bash allowlist, nothing else: any `pnpm` script; `gh issue view`; `gh issue comment` and add `needs-info` on its own issue; `gh pr create`; `gh run watch/view/list`; `gh pr checks`; `git status/diff/log/add/rm/commit`; `git push` of its own branch. No `git revert/reset/checkout/rebase`, no `curl`, no `gh api`, no other labels, no repo or CI settings.
- Read-only commands (`ls`, `grep`, `git show`, `git grep`, `git ls-files`) are always allowed.
- One plain command per Bash call: no `&&`, `;`, redirects or multi-line commands.
- File tools can't write outside the worktree. Shell commands run in an OS sandbox with no network (except `gh`, `git push`, and `pnpm verify:all`).
- No network means no new dependencies: `pnpm add` fails. Dependencies are installed from the lockfile before the run; a new one must already be on main, added by a human.
- Stop hook: on factory/issue-N it can't finish while the repo's `pnpm verify:all` fails, unless the issue has the `needs-info` label.
- `main` requires the `verify` CI check. Humans merge.
- Repo-specific rules (external APIs, secrets, test doubles) are in the repo's AGENTS.md. No API keys are available. Nobody looks at the screen: anything "checked by eye" isn't checked.
