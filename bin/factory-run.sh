#!/usr/bin/env bash
# factory-run <repo-dir> <issue-number>: implement one issue in its own worktree, open a PR.
set -euo pipefail
bin=$(cd "$(dirname "$0")" && pwd)
for f in progress.jq factory-settings.json spec-check.sh spec-schema.json gates.md; do
  [[ -f "$bin/$f" ]] || {
    echo "missing $bin/$f" >&2
    exit 1
  }
done

repo=$(cd "$1" && pwd)
issue=$2
name="$(basename "$repo")-issue-$issue"
runs="$bin/../runs"
mkdir -p "$runs"
receipt="$runs/$name-$(date +%Y%m%d-%H%M%S).jsonl"
branch="factory/issue-$issue"
wt="$(cd "$bin/.." && pwd)/worktrees/$name"

# A fresh checkout of origin/main for this run only. Your own checkout is never touched.
git -C "$repo" fetch -q origin main
# A leftover worktree: drop it if clean, refuse if a past run kept it for inspection.
if [[ -d "$wt" ]]; then
  if [[ -n "$(git -C "$wt" status --porcelain)" ]]; then
    echo "uncommitted work in $wt: inspect it, then git worktree remove --force it" >&2
    exit 1
  fi
  git -C "$repo" worktree remove "$wt"
fi
git -C "$repo" worktree add -q -B "$branch" "$wt" origin/main

# Spec check first: nothing installed, nothing spent on implementing. Not ready: stop here.
if ! spec=$("$bin/spec-check.sh" "$wt" "$issue"); then
  git -C "$repo" worktree remove "$wt"
  exit 1
fi
cd "$wt"
pnpm install --frozen-lockfile --reporter=silent # before Claude starts, outside its sandbox

# Ports per issue, so two runs' e2e servers don't collide.
export E2E_APP_PORT=$((5000 + issue)) E2E_STUB_PORT=$((6000 + issue))

# Factory files live in the worktree (the write block forbids /tmp). Git ignores them,
# so they are never committed and don't stop the worktree being cleaned up.
exclude="$(git -C "$wt" rev-parse --git-common-dir)/info/exclude"
for f in /factory-pr-body.md /factory-acceptance.json; do
  grep -qx "$f" "$exclude" 2>/dev/null || echo "$f" >>"$exclude"
done
# The criteria list the spec check produced, for the implementer to tick off.
jq '[.criteria[] | {id, text, check, passes: false, evidence: ""}]' "$spec" >factory-acceptance.json

prompt=$(
  cat <<PROMPT
Implement GitHub issue #$issue. Read it with: gh issue view $issue
You are on branch $branch, in a worktree made for this run. Stay on it.
Done means every acceptance criterion is met and the verify command in AGENTS.md exits 0.
factory-acceptance.json lists the criteria and the check for each. Do not change any id,
text or check. Set passes to true only after you ran that check and saw it pass, and put
the command and its result in evidence.
If the issue is ambiguous, or you are blocked (a command you need is denied or fails for
reasons outside the code), do not guess or work around it: post what you need with
gh issue comment $issue, add the needs-info label, and stop.
Use one plain command per Bash call: no && or ; chains, no redirects.
To wait for CI: gh run watch <run-id> --exit-status
When done: commit, push the branch, and open a PR using the pr skill. Multi-line commands
are denied, so write the PR body with the Write tool to factory-pr-body.md in the worktree
root, then run: gh pr create --base main --title "<title>" --body-file factory-pr-body.md
Finish with one line: OK or FAIL, then why.
PROMPT
)

claude -p "$prompt" \
  --settings "$bin/factory-settings.json" \
  --allowedTools "Read,Edit,Write,Skill" \
  "Bash(gh issue view *)" "Bash(gh issue comment $issue *)" \
  "Bash(gh issue edit $issue --add-label needs-info)" \
  "Bash(gh pr create *)" "Bash(pnpm *)" \
  "Bash(gh run watch *)" "Bash(gh run view *)" "Bash(gh run list *)" "Bash(gh pr checks *)" \
  "Bash(git status *)" "Bash(git diff *)" "Bash(git log *)" \
  "Bash(git add *)" "Bash(git rm *)" "Bash(git commit *)" "Bash(git push -u origin $branch)" \
  --permission-mode dontAsk \
  --max-turns 100 --max-budget-usd 10 \
  --output-format stream-json --verbose |
  tee "$receipt" | jq -r --unbuffered -f "$bin/progress.jq" || true

status=$(tail -1 "$receipt" | jq -r '
  if .is_error then "ERROR"
  else (.result // "" | split("\n") | map(select(length > 0)) | last // "no result") end')
# What the implementer claims, per criterion. A claim, not proof: lesson 7's reviewer checks it.
acc="$wt/factory-acceptance.json"
if [[ -f "$acc" ]]; then
  cp "$acc" "${receipt%.jsonl}-acceptance.json"
  status="$status · $(jq -r --slurpfile spec "$spec" '
    if map({id, text, check}) != ($spec[0].criteria | map({id, text, check})) then "criteria edited"
    else "\(map(select(.passes)) | length)/\(length) criteria claimed" end' "$acc")"
fi
# Pass the text as arguments, so quotes in $status can't break the AppleScript.
osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title (item 2 of argv)' \
  -e 'end run' "$status" "factory-run #$issue"

# Everything committed: drop the worktree (the branch stays). Otherwise keep it to inspect.
if [[ -z "$(git -C "$wt" status --porcelain)" ]]; then
  git -C "$repo" worktree remove "$wt"
else
  echo "worktree kept for inspection: $wt" >&2
fi
