#!/usr/bin/env bash
# factory-poll: the laptop trigger. A systemd user timer runs it every few minutes while
# you're logged in and awake (see bin/laptop-setup.sh). For each repo in `targets`, every
# open issue the repo owner labelled `factory-local` goes through factory-dispatch, one at
# a time. Clones live outside the factory: $FACTORY_CLONES, default ~/.local/share/factory/clones.
set -uo pipefail
bin=$(cd "$(dirname "$0")" && pwd)
factory=$(cd "$bin/.." && pwd)
clones=${FACTORY_CLONES:-${XDG_DATA_HOME:-$HOME/.local/share}/factory/clones}
log() { echo "$(date '+%F %T') $*"; }

# One poller at a time: a long run outlasts the timer's interval.
mkdir -p "$factory/runs"
lock="$factory/runs/poll.lock"
if ! (set -C; echo $$ >"$lock") 2>/dev/null; then
  if kill -0 "$(cat "$lock")" 2>/dev/null; then exit 0; fi
  echo $$ >"$lock"
fi
trap 'rm -f "$lock"' EXIT

# Run the same factory Actions runs: main. A failed pull (local edits, diverged) skips this poll.
# fetch + merge rather than pull, so a pull.rebase setting can't change what this does.
if ! { git -C "$factory" fetch -q && git -C "$factory" merge -q --ff-only '@{u}'; }; then
  log "factory: can't fast-forward to origin (local edits or diverged), skipping this poll"
  exit 0
fi

grep -vE '^[[:space:]]*(#|$)' "$factory/targets" | while read -r slug; do
  owner=${slug%%/*}
  dir="$clones/${slug#*/}"
  if [[ ! -d "$dir/.git" ]]; then
    mkdir -p "$clones"
    gh repo clone "$slug" "$dir" -- -q || { log "$slug: clone failed"; continue; }
  fi
  gh label create factory-local -R "$slug" --color 1d76db \
    --description "Run this issue through the factory on the laptop" >/dev/null 2>&1 || true
  for n in $(gh issue list -R "$slug" --label factory-local --state open --json number -q '.[].number'); do
    # Same rule as the Actions caller: only the owner's label starts a run.
    who=$(gh api --paginate "repos/$slug/issues/$n/events" \
      --jq '.[] | select(.event == "labeled" and .label.name == "factory-local") | .actor.login' | tail -1)
    if [[ "$who" != "$owner" ]]; then
      log "$slug#$n: labelled by '$who', not $owner, ignored"
      continue
    fi
    log "$slug#$n: start"
    "$bin/factory-dispatch.sh" "$dir" "$n" factory-local </dev/null
    log "$slug#$n: done (exit $?)"
  done
done
