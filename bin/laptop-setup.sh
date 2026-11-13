#!/usr/bin/env bash
# laptop-setup: make a Fedora laptop a factory trigger. Safe to rerun.
# Installs the tools, checks the logins, and installs a systemd *user* timer that runs
# factory-poll every 5 minutes while you're logged in. Nothing runs while the laptop is
# asleep or off; a run cut off by a suspend is picked up again (the label is still on).
# Run from a clone of the factory: bin/laptop-setup.sh
set -euo pipefail
factory=$(cd "$(dirname "$0")/.." && pwd)

# 1. Tools. bubblewrap + socat are Claude Code's Linux sandbox. Fedora uses SELinux, not
#    AppArmor, so the user-namespace fix CI needs doesn't apply here.
sudo dnf install -y -q git jq gh nodejs npm bubblewrap socat
npm config set prefix "$HOME/.local"
export PATH="$HOME/.local/bin:$PATH"
npm install -g --silent pnpm "@anthropic-ai/claude-code@$(cat "$factory/bin/claude-version")"
claude --version
bwrap --ro-bind / / true && echo "bubblewrap: works"

# 2. Logins: these are yours to do, once.
ok=1
gh auth status >/dev/null 2>&1 || { echo "-> run: gh auth login"; ok=0; }
gh auth setup-git # git push over https through gh
git config --global user.name >/dev/null || { echo "-> run: git config --global user.name/user.email"; ok=0; }
echo "-> if you haven't yet: run 'claude' once and /login"

# 3. The timer. Paths are filled in here, so no machine path is committed.
units="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
mkdir -p "$units"
cat >"$units/factory-poll.service" <<UNIT
[Unit]
Description=Factory: run issues labelled factory-local

[Service]
Type=oneshot
Environment=PATH=$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin
ExecStart=$factory/bin/factory-poll.sh
TimeoutStartSec=3h
UNIT
cat >"$units/factory-poll.timer" <<UNIT
[Unit]
Description=Factory: poll for factory-local issues every 5 minutes

[Timer]
# OnActiveSec: first poll 1 min after the timer starts (login, or enable --now).
# OnUnitInactiveSec: then 5 min after each poll finishes, so polls never overlap.
OnActiveSec=1min
OnUnitInactiveSec=5min

[Install]
WantedBy=timers.target
UNIT
systemctl --user daemon-reload
systemctl --user enable --now factory-poll.timer
systemctl --user list-timers factory-poll.timer --no-pager

((ok)) && echo "ready. Logs: journalctl --user -u factory-poll -f" || echo "finish the logins above, then label an issue factory-local"
