#!/usr/bin/env bash
# factory-stats: averages over every factory run, from the hidden stats line factory-dispatch
# puts in its issue comment. Covers both triggers (Actions receipts are gone after 14 days,
# the comments stay). Reads the repos in `targets`; only comments by the repo owner count.
set -euo pipefail
factory=$(cd "$(dirname "$0")/.." && pwd)

grep -vE '^[[:space:]]*(#|$)' "$factory/targets" | while read -r slug; do
  gh api --paginate "repos/$slug/issues/comments?per_page=100" --jq '.[]
    | select(.author_association == "OWNER")
    | .body | capture("<!-- factory-stats (?<j>\\{.*\\}) -->") | .j'
done | jq -sr '
  def avg(f): if length == 0 then 0 else (map(f) | add / length) end;
  def money: . * 100 | round / 100 | tostring | "$" + .;
  def row($group):
    [$group, length,
     "\((map(select(.result == "pr")) | length) * 100 / ([length, 1] | max) | round)%",
     (avg(.dur_s) / 60 | . * 10 | round / 10 | tostring),
     (avg(.cost) | money), (avg(.spec_cost) | money), (avg(.impl_cost) | money),
     (avg(.review_cost) | money), (avg(.turns) | round | tostring), (map(.cost) | add // 0 | money)];
  ["GROUP", "RUNS", "PR", "AVG_MIN", "AVG_$", "SPEC_$", "IMPL_$", "REVIEW_$", "TURNS", "TOTAL_$"],
  row("all"),
  (group_by(.trigger)[] | row("trigger=\(.[0].trigger)")),
  (group_by(.result)[] | row("result=\(.[0].result)")),
  (group_by(.repo)[] | row(.[0].repo))
  | @tsv' | column -t -s $'\t'
