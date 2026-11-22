#!/usr/bin/env bash
# Keeps ~/lockout at origin/main. On change: re-links the addon and pops a desktop notification
# so you know to /reload (or restart the client when the TOC's file list changed). Same loop as grimoire-sync.
set -u

REPO="${LOCKOUT_REPO:-$HOME/lockout}"
INTERVAL="${LOCKOUT_SYNC_INTERVAL:-15}"
WOW_DIR="${LOCKOUT_WOW_DIR:-$HOME/Faugus/battlenet/drive_c/Program Files (x86)/World of Warcraft}"
FLAVORS="${LOCKOUT_FLAVORS:-_forever_}"

notify() {
    echo "$1"
    command -v notify-send >/dev/null && notify-send -a Lockout -i applications-games "Lockout" "$1" || true
}

link_addon() {
    local IFS=,
    for flavor in $FLAVORS; do
        local addons="$WOW_DIR/$flavor/Interface/AddOns"
        [ -d "$WOW_DIR/$flavor" ] || continue
        [ "$(readlink "$addons/Lockout")" = "$REPO/Lockout" ] && continue
        mkdir -p "$addons"
        [ -d "$addons/Lockout" ] && [ ! -L "$addons/Lockout" ] && rm -rf "$addons/Lockout"   # a hand-copied install
        ln -sfn "$REPO/Lockout" "$addons/Lockout"
        notify "Lockout linked into $flavor"
    done
}

link_addon
while true; do
    link_addon
    if git -C "$REPO" fetch -q origin main 2>/dev/null; then
        local_rev=$(git -C "$REPO" rev-parse HEAD)
        remote_rev=$(git -C "$REPO" rev-parse origin/main)
        if [ "$local_rev" != "$remote_rev" ]; then
            changed=$(git -C "$REPO" diff --name-only "$local_rev" "$remote_rev")
            git -C "$REPO" reset -q --hard origin/main
            link_addon
            subject=$(git -C "$REPO" log -1 --format=%s)
            toc_lines=$(git -C "$REPO" diff "$local_rev" "$remote_rev" -- '*.toc' | grep -E '^[+-][^+-]' | grep -v '## Version' || true)
            if [ -n "$toc_lines" ]; then
                notify "Updated: $subject — TOC changed, restart the WoW client (a /reload is not enough)"
            elif grep -q '^Lockout/' <<<"$changed"; then
                notify "Updated: $subject — /reload to apply"
            fi
            if grep -q '^deploy/' <<<"$changed"; then
                "$REPO/deploy/install.sh" --units-only
                systemctl --user --no-block restart lockout-sync.service
            fi
        fi
    fi
    sleep "$INTERVAL"
done
