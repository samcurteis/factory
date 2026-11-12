#!/usr/bin/env bash
# Stop hook for the implementer: it can't finish while the target repo's checks fail.
# Lives in the factory (wired in bin/factory-settings.json), so every target gets it and
# the agent can't edit it. Contract: the target repo has a `pnpm verify:all` script.
# Exit 2 sends stderr back to Claude as the reason to keep going.
set -uo pipefail
cd "$CLAUDE_PROJECT_DIR"

# Nothing changed: nothing to verify.
if [[ -z "$(git status --porcelain)" && "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]]; then
  exit 0
fi

# A factory run that asked a question (needs-info on its issue) may stop unfinished.
branch=$(git branch --show-current)
if [[ $branch =~ ^factory/issue-([0-9]+)$ ]] &&
  gh issue view "${BASH_REMATCH[1]}" --json labels --jq '.labels[].name' | grep -qx needs-info; then
  exit 0
fi

if ! out=$(pnpm -s verify:all 2>&1); then
  {
    echo "pnpm verify:all failed. Fix it before finishing:"
    echo "$out" | tail -60
  } >&2
  exit 2
fi
