#!/usr/bin/env bash
# spec-check <checkout-dir> <issue-number>: is this issue safe to hand to an unattended run?
# Ready: print the spec file, exit 0. Not ready: say why, exit 1 (model findings also go on the issue).
set -euo pipefail
bin=$(cd "$(dirname "$0")" && pwd)
dir=$(cd "$1" && pwd)
issue=$2
cd "$dir" # gh finds the repo from here
main=$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")
# Use the GitHub account the app's settings.local.json names, as the implementer does.
gh_dir=$(jq -r '.env.GH_CONFIG_DIR // empty' "$main/.claude/settings.local.json" 2>/dev/null || true)
if [[ -n "$gh_dir" ]]; then export GH_CONFIG_DIR="$gh_dir"; fi
runs="$bin/../runs"
mkdir -p "$runs"
out="$runs/$(basename "$main")-issue-$issue-spec-$(date +%Y%m%d-%H%M%S).json"
json=$(gh issue view "$issue" --json title,body,state,labels,comments)
body=$(jq -r .body <<<"$json")

# The text under one "## Heading" (or "### Heading", which issue forms produce).
section() { awk -v h="$1" '
  /^#{2,3} / { on = (substr($0, index($0, " ") + 1) == h); next }
  on' <<<"$body"; }

# 1. Deterministic checks. Cheap, so they run first; any failure skips the model.
lint=()
[[ $(jq -r .state <<<"$json") == OPEN ]] || lint+=("Issue is not open.")
if jq -e '.labels[].name | select(. == "needs-info")' <<<"$json" >/dev/null; then
  lint+=("Has needs-info, which lets the Stop hook pass unfinished work. Answer, edit the issue, remove the label.")
fi
for h in "Goal" "Acceptance criteria" "How to verify"; do
  [[ -n "$(section "$h" | tr -d '[:space:]')" ]] || lint+=("Missing or empty section: $h.")
done
for n in $(section "Blocked by" | grep -oE '#[0-9]+' | tr -d '#'); do
  [[ $(gh issue view "$n" --json state -q .state) == CLOSED ]] || lint+=("Blocked by #$n, which is still open.")
done
while IFS= read -r cmd; do
  [[ -z "$cmd" || "$cmd" == '```'* ]] && continue
  [[ "$cmd" == "pnpm "* ]] || lint+=("Verify command the implementer can't run: $cmd")
done < <(section "How to verify")

if ((${#lint[@]} > 0)); then
  printf 'not ready: %s\n' "${lint[@]}" >&2
  exit 1
fi

# 2. Judgment: a read-only model. No shell, no network, user settings only (so not the
#    app's Stop hook), and its answer forced into the schema. It can't run gh, so the
#    issues this one links to are fetched here and handed over.
linked=$(for n in $(grep -oE '#[0-9]+' <<<"$body" | tr -d '#' | sort -un); do
  [[ $n == "$issue" ]] || gh issue view "$n" --json number,title,state,body
done | jq -s .)
prompt=$(
  printf '%s\n\n' "You check one GitHub issue before an unattended agent implements it. Do not change anything." \
    "The issue (JSON from gh):" "$json" \
    "Issues it links to:" "$linked" \
    "The implementer works under these rules:" "$(cat "$bin/gates.md")" \
    "Read the code, AGENTS.md, GLOSSARY.md and docs/adr in this checkout as needed. Then report:" \
    "criteria: every acceptance criterion, in order, with the exact check (test file and case, or command) that proves it. verifiable is false if no check the implementer can run under the rules proves it." \
    "conflicts: anything the issue asks for that the rules forbid or make impossible, including human-only steps not fenced off in Out of scope. Only real collisions: if it is fine, leave it out." \
    "questions: at most 3 decisions the issue leaves open that the user would notice if guessed wrong (what is shown, which data, what a test expects). Not naming or style. Skip anything the code, ADRs, glossary or linked issues already decide. Fewer is better: an empty list is a good result." \
    "Read the issue as one spec, not as a log of edits: two statements that disagree (often hints added in different rounds) are a question, even if each is clear on its own."
)
# 3. Skip the model if nothing it reads has changed since its last "ready": same prompt
#    (issue, comments, linked issues, gates), same schema, same code on main.
key=$({ printf '%s' "$prompt"; cat "$bin/spec-schema.json"; git rev-parse origin/main; } | shasum -a 256 | cut -c1-16)
for f in $(ls -t "$runs/$(basename "$main")-issue-$issue-spec-"*.json 2>/dev/null); do
  if jq -e --arg key "$key" '.ready and .key == $key' "$f" >/dev/null 2>&1; then
    echo "spec check: inputs unchanged since $(basename "$f"), not asked again" >&2
    echo "$f"
    exit 0
  fi
done

result=$(claude -p "$prompt" \
  --setting-sources user --settings "$bin/factory-settings.json" \
  --tools Read,Grep,Glob --allowedTools Read,Grep,Glob --permission-mode dontAsk \
  --json-schema "$(cat "$bin/spec-schema.json")" \
  --max-turns 30 --max-budget-usd 2 --output-format json </dev/null)
if ! jq -e .structured_output <<<"$result" >/dev/null; then
  echo "spec check: no structured output" >&2
  exit 1
fi

# 4. Ready is computed here from the lists, never taken from the model.
jq --argjson issue "$issue" --arg key "$key" '.structured_output + {issue: $issue, cost_usd: .total_cost_usd, key: $key} |
  .ready = ((.conflicts | length) == 0 and (.questions | length) == 0
            and (.criteria | length) > 0 and all(.criteria[]; .verifiable))' <<<"$result" >"$out"

if jq -e .ready "$out" >/dev/null; then
  echo "$out"
  exit 0
fi

comment=$(jq -r '
  "> *Spec check (factory): not ready for an unattended run.*\n",
  (if (.conflicts | length) > 0 then "**Conflicts with the factory gates**",
    (.conflicts[] | "- Issue says: \(.issue_says)\n  Gate: \(.gate)\n  Fix: \(.fix)"), "" else empty end),
  (if (.questions | length) > 0 then "**Open questions**",
    (.questions[] | "- \(.question)\n  Why: \(.why)\n  Suggested: \(.default)"), "" else empty end),
  (if any(.criteria[]; .verifiable | not) then "**Criteria no check can prove**",
    (.criteria[] | select(.verifiable | not) | "- \(.id): \(.text)"), "" else empty end),
  "Edit the issue, remove `needs-info`, then run again."' "$out")
gh issue comment "$issue" --body "$comment" >/dev/null
gh issue edit "$issue" --add-label needs-info >/dev/null
echo "not ready, see the comment on #$issue: $out" >&2
exit 1
