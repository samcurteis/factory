#!/usr/bin/env bash
# bench-reset <bench-repo-dir> [id...]: put the bench back to a clean start.
# Closes factory PRs and deletes factory/* branches, closes the old bench issues, then creates
# a fresh issue per bench/<id>/issue.md (all ids, or the ones named). Fresh issue numbers mean
# no answers, comments or cached spec/review receipts carry over from a previous run.
# Prints and saves the id → issue number map: runs/<repo>-bench-issues.tsv.
set -euo pipefail
bin=$(cd "$(dirname "$0")" && pwd)
factory=$(cd "$bin/.." && pwd)
repo=$(cd "$1" && pwd)
shift
cd "$repo"
gh_dir=$(jq -r '.env.GH_CONFIG_DIR // empty' .claude/settings.local.json 2>/dev/null || true)
if [[ -n "$gh_dir" ]]; then export GH_CONFIG_DIR="$gh_dir"; fi

# main must still be the baseline, or results aren't comparable with earlier runs.
git fetch -q --tags origin main
if [[ $(git rev-parse origin/main) != $(git rev-parse 'baseline^{commit}') ]]; then
  echo "origin/main is not at tag baseline: bench results won't be comparable. Retag or reset first." >&2
  exit 1
fi

if (($# > 0)); then ids=("$@"); else ids=($(cd "$factory/bench" && ls -d */ | tr -d /)); fi
for id in "${ids[@]}"; do
  [[ -f "$factory/bench/$id/issue.md" ]] || {
    echo "no bench/$id/issue.md" >&2
    exit 1
  }
done

# 1. Old runs: PRs closed with their branches, leftover branches and worktrees removed.
for pr in $(gh pr list --state open --json number,headRefName -q '.[] | select(.headRefName | startswith("factory/")) | .number'); do
  gh pr close "$pr" --delete-branch --comment "bench reset" >/dev/null
  echo "closed PR #$pr"
done
for b in $(git ls-remote --heads origin 'factory/*' | sed 's|.*refs/heads/||'); do
  git push -q origin --delete "$b"
  echo "deleted origin/$b"
done
for wt in "$factory/worktrees/$(basename "$repo")"-issue-*; do
  if [[ -d "$wt" ]]; then
    git worktree remove --force "$wt"
    echo "removed worktree $wt"
  fi
done
git worktree prune
for b in $(git branch --list 'factory/*' --format '%(refname:short)'); do git branch -q -D "$b"; done

# 2. Old bench issues closed (all of them, even when only some ids are recreated: one live set).
for n in $(gh issue list --label bench --state open --json number -q '.[].number'); do
  gh issue close "$n" --reason "not planned" --comment "bench reset" >/dev/null
  echo "closed issue #$n"
done

# 3. Fresh issues.
map="$factory/runs/$(basename "$repo")-bench-issues.tsv"
mkdir -p "$factory/runs"
: >"$map"
for id in "${ids[@]}"; do
  src="$factory/bench/$id/issue.md"
  title=$(head -1 "$src" | sed 's/^# //')
  url=$(tail -n +2 "$src" | gh issue create --title "$title" --label bench --body-file -)
  printf '%s\t%s\n' "$id" "${url##*/}" | tee -a "$map"
done
