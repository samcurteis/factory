#!/usr/bin/env bash
# review <worktree> <issue-number> <spec-file>: an independent check of the branch checked out in
# <worktree> against the spec's criteria. Prints the verdict, comments on the branch's PR.
# Exit 0 = approve, 1 = changes requested.
set -euo pipefail
bin=$(cd "$(dirname "$0")" && pwd)
wt=$(cd "$1" && pwd)
issue=$2
spec=$(cd "$(dirname "$3")" && pwd)/$(basename "$3")
cd "$wt"
main=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")
gh_dir=$(jq -r '.env.GH_CONFIG_DIR // empty' "$main/.claude/settings.local.json" 2>/dev/null || true)
if [[ -n "$gh_dir" ]]; then export GH_CONFIG_DIR="$gh_dir"; fi
branch=$(git branch --show-current)
base=${REVIEW_BASE:-origin/main} # override to re-review an old, merged branch
out="$bin/../runs/$(basename "$main")-issue-$issue-review-$(date +%Y%m%d-%H%M%S).json"

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
result=$(claude -p "$prompt" \
  --plugin-dir "$bin/.." --agent factory:reviewer \
  --setting-sources user --settings "$bin/factory-settings.json" \
  --allowedTools "Bash(pnpm *)" "Bash(git diff *)" "Bash(git log *)" "Bash(git show *)" \
  --permission-mode dontAsk \
  --json-schema "$(cat "$bin/review-schema.json")" \
  --max-turns 60 --max-budget-usd 3 --output-format json </dev/null)
if ! jq -e .structured_output <<<"$result" >/dev/null; then
  echo "review: no structured output" >&2
  exit 1
fi

# Approve is computed here: every spec criterion has a pass, and nothing is blocking.
jq --slurpfile spec "$spec" --argjson issue "$issue" '.structured_output + {issue: $issue, cost_usd: .total_cost_usd} |
  ([.criteria[] | select(.verdict == "pass") | .id]) as $passed |
  .approve = (all($spec[0].criteria[]; .id as $id | $passed | index($id)) and
              all(.findings[]; .severity != "blocking"))' <<<"$result" >"$out"

verdict=$(jq -r 'if .approve then "approve"
  else "changes: \([.criteria[] | select(.verdict != "pass")] | length) criteria not passed, \([.findings[] | select(.severity == "blocking")] | length) blocking" end' "$out")

pr=$(gh pr list --head "$branch" --json number -q '.[0].number')
if [[ -n "$pr" ]]; then
  comment=$(jq -r --arg verdict "$verdict" '
    def cell: tostring | gsub("\\|"; "\\|") | gsub("\n"; " ");
    "> *Factory review (agent): \($verdict).* It ran each check itself and never saw the implementer claims.\n",
    "| Criterion | Verdict | Ran | Observed |", "|---|---|---|---|",
    (.criteria[] | "| \(.id) | \(.verdict) | `\(.ran | cell)` | \(.observed | cell) |"),
    (if (.findings | length) > 0 then "\n**Findings**", (.findings[] | "- **\(.severity)** `\(.where)`: \(.issue)") else empty end)' "$out")
  gh pr comment "$pr" --body "$comment" >/dev/null
fi
echo "$verdict"
jq -e .approve "$out" >/dev/null
