#!/usr/bin/env bash
# factory-status [issue...]: one line per issue the factory has touched, read from runs/.
# Running? last spec, last review, total cost. No model, no network.
set -euo pipefail
runs="$(cd "$(dirname "$0")/.." && pwd)/runs"
cd "$runs"

names=$(ls | grep -oE '^.+-issue-[0-9]+' | sort -u)
if (($# > 0)); then names=$(grep -E -- "-issue-($(IFS='|'; echo "$*"))$" <<<"$names" || true); fi

printf '%-28s %-8s %-10s %-28s %8s  %s\n' ISSUE RUN SPEC REVIEW COST UPDATED
for name in $names; do
  run="-"
  if [[ -f "$name.lock" ]] && kill -0 "$(cat "$name.lock")" 2>/dev/null; then run="running"; fi

  # Newest first. The trailing - or . keeps issue-3 from matching issue-33.
  spec=$(ls -t "$name"-spec-*.json 2>/dev/null | head -1 || true)
  spec_state=$([[ -n "$spec" ]] && jq -r 'if .ready then "ready" else "not ready" end' "$spec" || echo "-")
  reviews=$(ls -t "$name"-*review-*.json 2>/dev/null | grep -v -- '-r[0-9]*\.json$' || true)
  review="-"
  if [[ -n "$reviews" ]]; then
    review=$(jq -r '"\(if .approve then "approve" else "changes" end) @\(.head // "?" | .[0:7])"' "$(head -1 <<<"$reviews")")
  fi

  # Cost: spec checks + merged reviews + implementer sessions. A resumed session's
  # total_cost_usd already includes its earlier calls, so take the last one per session.
  cost=$(
    {
      ls "$name"-spec-*.json 2>/dev/null | xargs -I{} jq '.cost_usd // 0' {}
      [[ -n "$reviews" ]] && xargs -I{} jq '.cost_usd // 0' {} <<<"$reviews"
      cat "$name"-2*.jsonl 2>/dev/null | jq -s '[.[] | select(.type == "result")]
        | group_by(.session_id) | map(max_by(.total_cost_usd).total_cost_usd) | add // 0'
    } | jq -s 'add // 0 | . * 100 | round / 100'
  )
  newest=$(ls -t "$name"[-.]* | head -1)
  updated=$(date -r "$newest" '+%Y-%m-%d %H:%M') # -r <file> = its mtime, on BSD and GNU date
  printf '%-28s %-8s %-10s %-28s %8s  %s\n' "$name" "$run" "$spec_state" "$review" "$(printf '$%.2f' "$cost")" "$updated"
done
