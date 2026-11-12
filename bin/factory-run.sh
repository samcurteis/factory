#!/usr/bin/env bash
# factory-run <repo-dir> <issue-number>: implement one issue in its own worktree, open a PR.
set -euo pipefail
bin=$(cd "$(dirname "$0")" && pwd)
factory=$(cd "$bin/.." && pwd)
for f in bin/progress.jq bin/factory-settings.json bin/settings.sh hooks/verify-on-stop.sh bin/spec-check.sh bin/spec-schema.json bin/gates.md \
  bin/review.sh bin/review-schema.json roles/implementer.md agents/reviewer.md .claude-plugin/plugin.json; do
  [[ -f "$factory/$f" ]] || {
    echo "missing $factory/$f" >&2
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

# One run per issue at a time. A lock whose process is gone is left over from a crash.
lock="$runs/$name.lock"
if ! (set -C; echo $$ >"$lock") 2>/dev/null; then
  if kill -0 "$(cat "$lock")" 2>/dev/null; then
    echo "#$issue is already running (pid $(cat "$lock"))" >&2
    exit 1
  fi
  echo $$ >"$lock"
fi
trap 'rm -f "$lock"' EXIT

# Each stage is skipped when its output already exists for the same inputs:
# spec (spec-check's cache), implement (the branch is on origin), review (approved at this HEAD).
# A pushed branch is continued, never reset to main. To start over: git push origin --delete <branch>.
git -C "$repo" fetch -q origin main
start=origin/main
if git -C "$repo" ls-remote --exit-code --heads origin "$branch" >/dev/null; then
  git -C "$repo" fetch -q origin "$branch"
  start="origin/$branch"
  if git -C "$repo" merge-base --is-ancestor "$start" origin/main; then
    echo "$branch is already merged into main. Delete it to start over: git push origin --delete $branch" >&2
    exit 1
  fi
fi
# A leftover worktree: drop it if clean, refuse if a past run kept it for inspection.
if [[ -d "$wt" ]]; then
  if [[ -n "$(git -C "$wt" status --porcelain)" ]]; then
    echo "uncommitted work in $wt: inspect it, then git worktree remove --force it" >&2
    exit 1
  fi
  git -C "$repo" worktree remove "$wt"
fi
git -C "$repo" worktree add -q -B "$branch" "$wt" "$start"

# Spec check first: nothing installed, nothing spent on implementing. Not ready: stop here.
if ! spec=$("$bin/spec-check.sh" "$wt" "$issue"); then
  git -C "$repo" worktree remove "$wt"
  exit 1
fi
cd "$wt"
# The GitHub account the app's settings.local.json names, for this script's own gh calls.
gh_dir=$(jq -r '.env.GH_CONFIG_DIR // empty' "$repo/.claude/settings.local.json" 2>/dev/null || true)
if [[ -n "$gh_dir" ]]; then export GH_CONFIG_DIR="$gh_dir"; fi
pnpm install --frozen-lockfile --reporter=silent # before Claude starts, outside its sandbox

# Ports per issue, so two runs' e2e servers don't collide (fitness-tracker reads these; others ignore them).
export E2E_APP_PORT=$((5000 + issue)) E2E_STUB_PORT=$((6000 + issue))

# Factory files live in the worktree (the write block forbids /tmp). Git ignores them,
# so they are never committed and don't stop the worktree being cleaned up.
exclude="$(git -C "$wt" rev-parse --git-common-dir)/info/exclude"
for f in /factory-pr-body.md /factory-acceptance.json; do
  grep -qx "$f" "$exclude" 2>/dev/null || echo "$f" >>"$exclude"
done
# The criteria list the spec check produced, for the implementer to tick off.
jq '[.criteria[] | {id, text, check, passes: false, evidence: ""}]' "$spec" >factory-acceptance.json

# The role (rules for every run) is a file in the factory, appended to Claude Code's own
# system prompt. Only this run's facts go in the task.
task="Implement GitHub issue #$issue (read it with: gh issue view $issue). Branch: $branch."

# One implementer call, logged to the receipt. Extra flags (a fix round's --resume) follow the prompt.
# FACTORY_STAGE/FACTORY_DIR switch on the Stop hook in factory-settings.json for this call only:
# spec check and reviewers share the settings file but must not be gated.
implement() {
  FACTORY_STAGE=implement FACTORY_DIR="$factory" claude -p "$@" \
    --append-system-prompt-file "$factory/roles/implementer.md" \
    --settings "$("$bin/settings.sh")" \
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
    tee -a "$receipt" | jq -r --unbuffered -f "$bin/progress.jq" || true
  session=$(jq -r 'select(.type == "result") | .session_id' "$receipt" 2>/dev/null | tail -1)
}

# The implementer session to send fix rounds to: this run's, or the last run's on a continued branch.
session=""
if [[ $start == origin/main ]]; then
  implement "$task"
else
  echo "continuing $branch from origin: implement skipped" >&2
  for f in $(ls -t "$runs/$name"-2*.jsonl 2>/dev/null); do
    session=$(jq -r 'select(.type == "result") | .session_id' "$f" | tail -1)
    if [[ -n "$session" ]]; then break; fi
  done
fi

# Approved at exactly this commit before? Then there's nothing new to review.
approved_at() {
  for f in "$runs/$name"-*review-*.json; do
    [[ $f == *-r[0-9]*.json ]] && continue
    jq -e --arg head "$1" '.approve and .head == $head' "$f" >/dev/null 2>&1 && return 0
  done
  return 1
}

# Review. While the reviewers ask for changes, send their report back to the same
# implementer session: at most 2 fix rounds. Each round's report is a file in runs/.
review="not run (no commits)"
rc=0
if approved_at "$(git -C "$wt" rev-parse HEAD)"; then
  review="already approved at this commit"
elif [[ -n "$(git -C "$wt" log --oneline origin/main..HEAD)" ]]; then
  for round in 0 1 2; do
    report="${receipt%.jsonl}-review-$round.json"
    rc=0
    review=$("$bin/review.sh" "$wt" "$issue" "$spec" "$report") || rc=$?
    review=${review:-broke, see runs/}
    # Stop on approve (0), a broken review (2), the last round, or a needs-info from the implementer.
    if ((rc != 1 || round == 2)); then break; fi
    if gh issue view "$issue" --json labels -q '.labels[].name' | grep -qx needs-info; then break; fi
    fix=$(jq -r --argjson round $((round + 1)) --arg branch "$branch" '
      "\(.reviewers) reviewers checked your branch and asked for changes (fix round \($round) of 2). They never saw your evidence.\n",
      (.criteria[] | select(.verdict != "pass") | "- \(.id) \(.verdict): \(.observed)"),
      (.findings[] | select(.severity == "blocking" or .criterion != "none") | "- \(.where): \(.issue)"),
      "\nFix this on the same branch: cover each case with a test, make it pass, update factory-acceptance.json, commit, then git push -u origin \($branch). The PR updates itself: do not open another.",
      "If you think a point is wrong, change nothing for it and say why in your final line."' "$report")
    if [[ -n "$session" ]]; then
      implement "$fix" --resume "$session"
    else
      implement "$task"$'\n\n'"$fix" # no session found: a fresh implementer, told the task too
    fi
  done
  # Not approved after the last round: back to draft, so it can't be merged by mistake.
  if ((rc != 0)); then
    pr=$(gh pr list --head "$branch" --json number -q '.[0].number')
    if [[ -n "$pr" ]] && gh pr ready "$pr" --undo >/dev/null 2>&1; then review="$review · PR #$pr is a draft"; fi
  fi
fi

status="no implementer call this run"
if [[ -f "$receipt" ]]; then
  status=$(tail -1 "$receipt" | jq -r '
    if .is_error then "ERROR"
    else (.result // "" | split("\n") | map(select(length > 0)) | last // "no result") end')
fi
# What the implementer claims, per criterion. A claim, not proof: the reviewers check it.
acc="$wt/factory-acceptance.json"
if [[ -f "$receipt" && -f "$acc" ]]; then
  cp "$acc" "${receipt%.jsonl}-acceptance.json"
  status="$status · $(jq -r --slurpfile spec "$spec" '
    if map({id, text, check}) != ($spec[0].criteria | map({id, text, check})) then "criteria edited"
    else "\(map(select(.passes)) | length)/\(length) criteria claimed" end' "$acc")"
fi

status="$status · review: $review"

# Pass the text as arguments, so quotes in $status can't break the AppleScript.
osascript -e 'on run argv' -e 'display notification (item 1 of argv) with title (item 2 of argv)' \
  -e 'end run' "$status" "factory-run #$issue"

# Everything committed: drop the worktree (the branch stays). Otherwise keep it to inspect.
if [[ -z "$(git -C "$wt" status --porcelain)" ]]; then
  git -C "$repo" worktree remove "$wt"
else
  echo "worktree kept for inspection: $wt" >&2
fi
