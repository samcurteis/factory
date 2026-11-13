#!/usr/bin/env bash
# factory-dispatch <repo-dir> <issue> <trigger-label>: one triggered run, start to finish.
# Both triggers use it: the Actions workflow (label `factory`) and the laptop poller
# (label `factory-local`). Marks the issue factory:running, runs factory-run, then comments
# the outcome with a hidden stats line (read by factory-stats) and removes both labels,
# so adding the trigger label again runs it again. Exits with factory-run's status.
set -uo pipefail
bin=$(cd "$(dirname "$0")" && pwd)
factory=$(cd "$bin/.." && pwd)
repo=$(cd "$1" && pwd)
issue=$2
label=$3
trigger=$([[ -n "${GITHUB_ACTIONS:-}" ]] && echo actions || echo local)
cd "$repo" # gh finds the repo from here
gh_dir=$(jq -r '.env.GH_CONFIG_DIR // empty' .claude/settings.local.json 2>/dev/null || true)
if [[ -n "$gh_dir" ]]; then export GH_CONFIG_DIR="$gh_dir"; fi

name="$(basename "$repo")-issue-$issue"
runs="$factory/runs"
mkdir -p "$runs"
log="$runs/$name-$(date +%Y%m%d-%H%M%S).log"
marker="$runs/.dispatch-$$"
touch "$marker"
trap 'rm -f "$marker"' EXIT

gh label create factory:running --color fbca04 --description "The factory is working on this issue" >/dev/null 2>&1 || true
gh issue edit "$issue" --add-label factory:running >/dev/null || true

start=$(date +%s)
"$bin/factory-run.sh" "$repo" "$issue" 2>&1 | tee "$log"
rc=${PIPESTATUS[0]}
dur=$(($(date +%s) - start))
status=$(grep -v '^[[:space:]]*$' "$log" | tail -1)

# What came out. Stopped = factory-run refused, or the spec check said not ready.
labels=$(gh issue view "$issue" --json labels -q '.labels[].name')
pr=$(gh pr list --head "factory/issue-$issue" --state open --json number,isDraft -q '.[0] // empty')
if grep -qx needs-info <<<"$labels"; then
  result=needs-info
elif ((rc != 0)); then
  result=stopped
elif [[ -z "$pr" ]]; then
  result=no-pr
elif jq -e .isDraft <<<"$pr" >/dev/null; then
  result=draft
else
  result=pr
fi

# Cost of this run only, from the files it wrote. A resumed implementer session reports its
# running total, so subtract what earlier runs already recorded for the same session.
new() { find "$runs" -maxdepth 1 -name "$1" -newer "$marker" | sort; }
old() { find "$runs" -maxdepth 1 -name "$1" ! -newer "$marker" | sort; }
stats=$(jq -cn \
  --slurpfile spec <(new "$name-spec-*.json" | xargs cat /dev/null) \
  --slurpfile review <(new "$name-*review-[0-9].json" | xargs cat /dev/null) \
  --slurpfile impl <(new "$name-2*.jsonl" | xargs cat /dev/null) \
  --slurpfile before <(old "$name-2*.jsonl" | xargs cat /dev/null) \
  --arg repo "$(gh repo view --json nameWithOwner -q .nameWithOwner)" --argjson issue "$issue" \
  --arg trigger "$trigger" --arg result "$result" --argjson dur "$dur" --arg at "$(date -u +%FT%TZ)" '
  def r2: . * 100 | round / 100;
  def results: map(select(.type == "result"));
  ($before | results | map({(.session_id): .total_cost_usd}) | reduce .[] as $o ({};
     reduce ($o | to_entries[]) as $e (.; .[$e.key] = ([.[$e.key] // 0, $e.value] | max)))) as $prev |
  ($impl | results) as $calls |
  ($calls | group_by(.session_id) | map((map(.total_cost_usd) | max) - ($prev[.[0].session_id] // 0)) | add // 0) as $impl_cost |
  ($spec | map(.cost_usd // 0) | add // 0) as $spec_cost |
  ($review | map(.cost_usd // 0) | add // 0) as $review_cost |
  {v: 1, repo: $repo, issue: $issue, trigger: $trigger, result: $result, at: $at, dur_s: $dur,
   cost: ($spec_cost + $impl_cost + $review_cost | r2), spec_cost: ($spec_cost | r2),
   impl_cost: ($impl_cost | r2), review_cost: ($review_cost | r2),
   turns: ($calls | map(.num_turns // 0) | add // 0), review_rounds: ($review | length)}')

link=""
if [[ -n "${GITHUB_RUN_ID:-}" ]]; then
  link=" · [log and receipts]($GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID)"
fi
body="> *factory-run ($result, $trigger, $((dur / 60))m, \$$(jq -r .cost <<<"$stats")):* ${status:-no output}$link

<!-- factory-stats $stats -->"
gh issue comment "$issue" --body "$body" >/dev/null || echo "could not comment on #$issue" >&2
# The label means "run this now". Removing it lets you add it again to rerun.
gh issue edit "$issue" --remove-label "$label" --remove-label factory:running >/dev/null 2>&1 || true
exit "$rc"
