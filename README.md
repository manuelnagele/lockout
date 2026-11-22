# Lockout

How many dungeon and raid entries you have left on **WoW: Forever**: the server allows **5 instances per hour** and
**30 per day** per character, rolling. The game doesn't show this counter; Lockout keeps it for you and tells you
when the next slot frees, so a reset doesn't put you outside the dungeon.

## What it shows

- **Five diamonds** on [Deadbeat](https://github.com/manuelnagele/deadbeat)'s bar: one per slot this hour, lit when
  free. With 1 or 0 left, a live countdown to the next free slot.
- **A big green/red indicator** you can place anywhere (shift-drag): green when a slot is free, red when you'd have
  to wait. Made for waiting on an alt while your main's instances reset.
- **The tooltip:** every entry still holding a slot, with the time it frees; your other characters' slots too.
- **Warnings:** a chat note at 1 left and at 0; logging out inside a dungeon with 0 left raises a raid warning
  ("a reset now puts you outside"), with time to cancel.

## How it counts

- An entry counts when you enter a dungeon or raid for the first time, or after a reset (the game's "… has been
  reset." message or a relog since your last visit). Going back into the same instance within 30 minutes doesn't count.
- A slot frees **60 minutes after the entry, plus a 2-minute safety margin**.
- When the game says "You have entered too many instances recently", missing entries are added as estimates (`~`).
- The game has no API for this counter: entries Lockout didn't see (before you installed it, on another PC) are
  missing until that message corrects the count.

## Settings

The gear on Deadbeat's bar → **Lockout**: the big indicator on/off, forget this character's lockouts. Which places the
diamonds show in: Deadbeat's Bar page. Commands: `/lockout` (this hour's entries) · `/lockout debug`.

Without Deadbeat, Lockout still counts and shows a line under the minimap.

**For other addons:** `Lockout.Status()` → `{ hourLeft, hourUsed, nextFree, dayLeft, dayUsed, estimated }`,
`Lockout.Text()`.

## Install

Copy the `Lockout` folder into `World of Warcraft/_forever_/Interface/AddOns/`. Best with
[Deadbeat](https://github.com/manuelnagele/deadbeat).

## Development

```
luajit tests/run.lua                 # the counting rules
luajit tests/smoke.lua               # the whole addon on Deadbeat (needs ../deadbeat)
```
Releases: push a tag `vX.Y.Z` matching the TOC's version; CI packages the zip onto GitHub Releases.
`deploy/` is the author's Linux setup that keeps a game install in sync with this repo (optional).

License: MIT.
