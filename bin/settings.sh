#!/usr/bin/env bash
# settings: print the settings JSON every claude call gets (pass it to --settings).
# factory-settings.json plus what depends on where the factory lives, worked out here so no
# machine path is committed: the bench answers (bench/) are unreadable to every stage.
set -euo pipefail
factory=$(cd "$(dirname "$0")/.." && pwd)
jq -c --arg bench "/$factory/bench/**" \
  '.permissions.deny += ["Read(\($bench))"]' "$factory/bin/factory-settings.json"
