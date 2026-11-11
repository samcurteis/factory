#!/usr/bin/env bash
# review <worktree> <issue-number> <spec-file> [out-file]: $REVIEWERS (default 2) independent
# reviews of the branch checked out in <worktree>, against the spec's criteria, merged.
# Prints the verdict, comments on the branch's PR.
# Exit 0 = approve, 1 = changes requested, 2 = the review itself broke.
set -euo pipefail
bin=$(cd "$(dirname "$0")" && pwd)
wt=$(cd "$1" && pwd)
issue=$2
spec=$(cd "$(dirname "$3")" && pwd)/$(basename "$3")
# An out-file is made absolute before the cd, so a relative path means relative to you.
out=""
if [[ -n "${4:-}" ]]; then out=$(cd "$(dirname "$4")" && pwd)/$(basename "$4"); fi
cd "$wt"
main=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")
gh_dir=$(jq -r '.env.GH_CONFIG_DIR // empty' "$main/.claude/settings.local.json" 2>/dev/null || true)
if [[ -n "$gh_dir" ]]; then export GH_CONFIG_DIR="$gh_dir"; fi
branch=$(git branch --show-current)
base=${REVIEW_BASE:-origin/main} # override to re-review an old, merged branch
n=${REVIEWERS:-2}
out=${out:-"$bin/../runs/$(basename "$main")-issue-$issue-review-$(date +%Y%m%d-%H%M%S).json"}

# What the reviewer sees: the ticket, the spec's criteria, the rules, and the code.
# Not the implementer's transcript, PR body or ticked criteria file: those are claims.
prompt=$(
  printf '%s\n\n' "Review branch $branch (HEAD $(git rev-parse --short HEAD)). The change under review is: git diff $base...HEAD" \
    "The ticket (JSON from gh):" "$(gh issue view "$issue" --json title,body)" \
    "Acceptance criteria and the check the spec stage expected for each:" \
    "$(jq '[.criteria[] | {id, text, check}]' "$spec")" \
    "The rules the implementer worked under:" "$(cat "$bin/gates.md")" \
    "Give a verdict for every criterion id above, then your findings."
)

# Each review is a sample: same prompt, fresh context, different result. Take several.
# One after another: in parallel they'd share .next and the e2e ports.
raws=()
for i in $(seq 1 "$n"); do
  raw="${out%.json}-r$i.json"
  claude -p "$prompt" \
    --plugin-dir "$bin/.." --agent factory:reviewer \
    --setting-sources user --settings "$bin/factory-settings.json" \
    --allowedTools "Bash(pnpm *)" "Bash(git diff *)" "Bash(git log *)" "Bash(git show *)" \
    --permission-mode dontAsk \
    --json-schema "$(cat "$bin/review-schema.json")" \
    --max-turns 60 --max-budget-usd 3 --output-format json </dev/null >"$raw" || true
  if ! jq -e .structured_output "$raw" >/dev/null 2>&1; then
    echo "review: reviewer $i gave no structured output ($raw)" >&2
    exit 2
  fi
  raws+=("$raw")
done

# Merge, here, not by a model:
# - a finding that names a criterion makes that reviewer's pass unproven;
# - a criterion passes only if every reviewer passed it (worst verdict wins);
# - approve = every spec criterion passes and no finding is blocking.
jq -s --slurpfile spec "$spec" --argjson issue "$issue" --arg head "$(git rev-parse HEAD)" '
  def rank: {"pass": 0, "unproven": 1, "fail": 2}[.];
  [.[] | .structured_output as $r | {
    cost: .total_cost_usd,
    findings: $r.findings,
    criteria: [$r.criteria[] | .id as $id |
      if .verdict == "pass" and any($r.findings[]; .criterion == $id)
      then . + {verdict: "unproven", observed: ("Said pass, but its own finding names this criterion. " + .observed)}
      else . end]}] as $runs |
  {issue: $issue, head: $head, reviewers: ($runs | length), cost_usd: ($runs | map(.cost) | add),
   criteria: [$spec[0].criteria[] | .id as $id |
     [$runs[] | first(.criteria[] | select(.id == $id)) // {id: $id, verdict: "unproven", ran: "none", observed: "No verdict given."}] as $v |
     ($v | max_by(.verdict | rank)) + {votes: ($v | map(.verdict))}],
   findings: [$runs | to_entries[] | (.key + 1) as $k | .value.findings[] | . + {reviewer: $k}]} |
  .approve = (all(.criteria[]; .verdict == "pass") and all(.findings[]; .severity != "blocking"))' \
  "${raws[@]}" >"$out"

verdict=$(jq -r 'if .approve then "approve (\(.reviewers) reviewers, \([.findings[] | select(.severity == "note")] | length) notes to read)"
  else "changes: \([.criteria[] | select(.verdict != "pass")] | length) criteria not passed, \([.findings[] | select(.severity == "blocking")] | length) blocking" end' "$out")

pr=$(gh pr list --head "$branch" --json number -q '.[0].number')
if [[ -n "$pr" ]]; then
  comment=$(jq -r --arg verdict "$verdict" '
    def cell: tostring | gsub("\\|"; "\\|") | gsub("\n"; " ");
    "> *Factory review (\(.reviewers) agents): \($verdict).* Each ran the checks itself and never saw the implementer claims. A criterion passes only if every reviewer passed it.\n",
    "| Criterion | Verdict | Votes | Ran | Observed |", "|---|---|---|---|---|",
    (.criteria[] | "| \(.id) | \(.verdict) | \(.votes | join(", ")) | `\(.ran | cell)` | \(.observed | cell) |"),
    (if (.findings | length) > 0 then "\n**Findings**", (.findings[] | "- **\(.severity)** `\(.where)` (\(.criterion), reviewer \(.reviewer)): \(.issue)") else empty end)' "$out")
  gh pr comment "$pr" --body "$comment" >/dev/null
fi
echo "$verdict"
jq -e .approve "$out" >/dev/null
