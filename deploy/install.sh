#!/usr/bin/env bash
# One-time setup on the gaming box (also re-run by lockout-sync when deploy/ changes):
#   git clone github-lockout:manuelnagele/lockout ~/lockout && ~/lockout/deploy/install.sh
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
UNITS="$HOME/.config/systemd/user"
mkdir -p "$UNITS"
sed "s|@REPO@|$REPO|g" "$REPO/deploy/lockout-sync.service" > "$UNITS/lockout-sync.service"
systemctl --user daemon-reload

[ "${1:-}" = "--units-only" ] && exit 0

systemctl --user enable --now lockout-sync.service
systemctl --user --no-pager status lockout-sync.service | grep -E '●|Active'
