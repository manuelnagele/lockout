-- luajit tests/run.lua  (from the repo root)
local ns = {}
assert(loadfile("Lockout/Core.lua"))("Lockout", ns)
local Core = ns.Core
local failures = 0
local function check(name, cond)
    if not cond then failures = failures + 1 print("FAIL " .. name) else print("ok   " .. name) end
end

local T = 1000000
check("first entry counts", Core.isNewEntry(nil, T))
check("back in after a death, no reset: same instance", not Core.isNewEntry({ at = T, leftAt = T + 300 }, T + 400))
check("reset since entering: new", Core.isNewEntry({ at = T, leftAt = T + 300, resetAt = T + 320 }, T + 330))
check("old reset doesn't count", not Core.isNewEntry({ at = T + 100, resetAt = T, leftAt = T + 200 }, T + 250))
check("left > 30 min ago: new", Core.isNewEntry({ at = T, leftAt = T + 60 }, T + 60 + 1801))
check("still inside (no leftAt), re-check: same", not Core.isNewEntry({ at = T }, T + 5000))

check("relog after leaving: new", Core.isNewEntry({ at = T, leftAt = T + 300 }, T + 400, T + 350))
check("relog before the last visit doesn't count", not Core.isNewEntry({ at = T + 100, leftAt = T + 300 }, T + 400, T + 50))
check("login inside the instance (logged out in it): new", Core.isNewEntry({ at = T }, T + 900, T + 800))

local map, copy = Core.instanceCopy("Creature-0-4170-349-21543-11517-00002A6F1B")
check("instance copy from a creature guid", map == 349 and copy == 21543)
check("players have no copy", Core.instanceCopy("Player-4170-0A1B2C3D") == nil)
check("nil/secret-like input", Core.instanceCopy(nil) == nil)
check("same copy, counted by heuristic -> remove", Core.confirm(true, 21543, 21543) == "remove")
check("same copy, not counted -> keep", Core.confirm(false, 21543, 21543) == "keep")
check("new copy, missed by heuristic -> add", Core.confirm(false, 21543, 30001) == "add")
check("new copy, counted -> keep", Core.confirm(true, 21543, 30001) == "keep")
check("first visit ever -> keep heuristic", Core.confirm(true, nil, 30001) == "keep")

local entries = { { t = T }, { t = T + 600 }, { t = T + 1200 } }
local s = Core.status(entries, T + 1800)
check("hour used/left", s.hourUsed == 3 and s.hourLeft == 2)
check("next free = oldest end + 1h + margin", s.nextFree == T + 3600 + Core.MARGIN)
s = Core.status(entries, T + 3600 + Core.MARGIN)
check("oldest aged out", s.hourUsed == 2 and s.nextFree == T + 600 + 3600 + Core.MARGIN)
check("held an hour after entering, however long you stayed", Core.status({ { t = T, seen = T + 900 } }, T + 3600 + Core.MARGIN).hourUsed == 0)
check("day still counts all", s.dayUsed == 3)

local five = { { t = T }, { t = T + 1 }, { t = T + 2 }, { t = T + 3 }, { t = T + 4 } }
check("five used = 0 left", Core.status(five, T + 10).hourLeft == 0)

local two = { { t = T + 100 }, { t = T + 200 } }
check("calibrate pads to 5", Core.calibrate(two, T + 300) == 3 and Core.status(two, T + 300).hourLeft == 0)
check("calibrated is estimated", Core.status(two, T + 300).estimated)
check("synthetic ones are held a full hour from the message", Core.status(two, T + 300 + 3600 + Core.MARGIN).hourUsed == 0
    and Core.status(two, T + 300 + 3600 + Core.MARGIN - 1).hourUsed == 3)
check("calibrate no-op when full", Core.calibrate(five, T + 10) == 0)

check("prune keeps 24 h", #Core.prune({ { t = T }, { t = T + 90000 } }, T + 90001) == 1)
local p = Core.pattern("%s has been reset.")
check("reset pattern", ("Maraudon has been reset."):match(p) == "Maraudon")

local held = Core.held({ { t = T + 100, zone = "B" }, { t = T, zone = "A" }, { t = T - 4000, zone = "old" } }, T + 200)
check("held: in the window, oldest first, free = +1h", #held == 2 and held[1].zone == "A" and held[1].free == T + 3600 + Core.MARGIN)
check("countdown", Core.countdown(23 * 60 + 5) == "23m" and Core.countdown(65) == "1m 05s" and Core.countdown(9) == "9s")

-- 2026-11-21: the entry at 18:51:38 worked with 17:59 18:14 18:25 18:46 in the hour before (4 held).
do
    local real = {}
    for _, t in ipairs({ 1795279473, 1795280347, 1795281253, 1795281903, 1795283209 }) do
        real[#real + 1] = { t = t, zone = "Maraudon" }
    end
    check("18:51 had a free slot", Core.status(real, 1795283498).hourLeft == 1)
    Core.backfill(real, {}, 1795283498)
    check("backfill: ends at the next entry", real[1].seen == 1795280347)
end

print(failures == 0 and "all passed" or (failures .. " failed"))
os.exit(failures == 0 and 0 or 1)
