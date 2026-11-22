-- Lockout core: which entries count, how many are left, when the next slot frees up.
-- No WoW calls, so it runs under LuaJIT in tests (tests/run.lua).
local _, ns = ...
ns = ns or {}
local Core = {}
ns.Core = Core

Core.PER_HOUR = 5
Core.PER_DAY = 30
Core.HOUR = 3600
Core.DAY = 86400
Core.SAME_INSTANCE = 1800   -- back into the same dungeon within 30 min of leaving, no reset seen = same instance
Core.MARGIN = 120           -- safety on top of the hour (the reset lands a little after the logout)

-- A slot is held for an hour after entering (+ margin). 0.7 tried "an hour after the instance ended" after a port to
-- Orgrimmar at 17:18 on 2026-11-21, but an entry at 18:51 contradicted it, and the port came without the usual
-- "too many instances" message: probably something else. Entering fits all other 12 entries that day (user: 0.8).
-- e.seen (the last time inside / the reset) is still recorded, for the next time the data disagrees.
function Core.freeAt(e)
    return e.t + Core.HOUR + Core.MARGIN
end

-- Entries saved before 0.7 have no e.seen: the instance ended no later than the next entry (the reset came before
-- it), or another character's login after it (the bank-alt reset), else assume 30 min. Fills only what's missing.
function Core.backfill(entries, logins, now)
    table.sort(entries, function(a, b) return a.t < b.t end)
    for i, e in ipairs(entries) do
        if not e.seen then
            local nxt = entries[i + 1]
            local seen = nxt and nxt.t
            if not seen then
                for _, l in ipairs(logins or {}) do
                    if l > e.t and (not seen or l < seen) then seen = l end
                end
            end
            e.seen = math.min(seen or (e.t + 1800), now)
        end
    end
end

-- Is entering `zone` at `now` a new instance? last = {at, leftAt, resetAt} for that zone (or nil);
-- loginAt = the last real login (not a /reload): relogging between two visits resets a solo instance.
function Core.isNewEntry(last, now, loginAt)
    if not last then return true end
    if last.resetAt and last.resetAt >= last.at then return true end
    if loginAt and loginAt > last.at then return true end
    if last.leftAt and now - last.leftAt > Core.SAME_INSTANCE then return true end
    return false
end

-- "Creature-0-<server>-<map>-<instance copy>-<npc>-<spawn>": the 5th part identifies this copy of the dungeon,
-- so a reset gives the same map a different number. Returns map, copy for creatures/vehicles, else nil.
function Core.instanceCopy(guid)
    if type(guid) ~= "string" then return nil end
    local kind, _, _, map, copy = guid:match("^(%a+)%-(%d+)%-(%d+)%-(%d+)%-(%d+)")
    if kind ~= "Creature" and kind ~= "Vehicle" then return nil end
    map, copy = tonumber(map), tonumber(copy)
    if not map or not copy or copy == 0 then return nil end
    return map, copy
end

-- The first mob seen settles a provisional decision: counted = what the heuristic did on entry,
-- prev = the copy number of the last visit (nil if unknown), copy = the one seen now.
-- Returns "keep" | "remove" (heuristic counted a re-entry) | "add" (heuristic missed a new copy).
function Core.confirm(counted, prev, copy)
    if not prev or not copy then return "keep" end
    if copy == prev then return counted and "remove" or "keep" end
    return counted and "keep" or "add"
end

function Core.prune(entries, now)
    local keep = {}
    for _, e in ipairs(entries) do
        if now - e.t < Core.DAY then keep[#keep + 1] = e end
    end
    return keep
end

-- {hourUsed, hourLeft, nextFree (epoch or nil), dayUsed, dayLeft, dayFree (epoch: when the day's oldest entry
-- frees a slot, only with none left today), estimated}
function Core.status(entries, now)
    local hour, day, nextFree, estimated = 0, 0, nil, false
    local oldest
    for _, e in ipairs(entries) do
        if now - e.t < Core.DAY then
            day = day + 1
            if not oldest or e.t < oldest then oldest = e.t end
        end
        local free = Core.freeAt(e)
        if now < free then
            hour = hour + 1
            if not nextFree or free < nextFree then nextFree = free end
            estimated = estimated or e.synthetic or false
        end
    end
    local left = math.max(0, Core.PER_HOUR - hour)
    local dayLeft = math.max(0, Core.PER_DAY - day)
    return {
        hourUsed = hour, hourLeft = left, dayUsed = day, dayLeft = dayLeft,
        dayFree = (dayLeft == 0 and oldest) and (oldest + Core.DAY + Core.MARGIN) or nil,
        nextFree = nextFree, estimated = estimated,
    }
end

-- Can you enter now, and if not, when? The hour and the day both have to allow it.
-- Returns free (bool), at (epoch or nil), why ("hour" | "day" | nil)
function Core.verdict(s)
    if s.dayLeft == 0 then return false, s.dayFree, "day" end
    if s.hourLeft == 0 then return false, s.nextFree, "hour" end
    return true, nil, nil
end

-- The game said "too many instances": at least PER_HOUR entries happened in the last hour. Pad with
-- synthetic entries at the oldest known time in the window (or now), so the count can't claim free slots.
function Core.calibrate(entries, now)
    local s = Core.status(entries, now)
    local missing = Core.PER_HOUR - s.hourUsed
    if missing <= 0 then return 0 end
    for _ = 1, missing do entries[#entries + 1] = { t = now, seen = now, zone = "?", synthetic = true } end
    return missing
end

-- Entries still holding a slot (oldest first) with the time each frees up; ref = the stored entry.
function Core.held(entries, now)
    local out = {}
    for _, e in ipairs(entries) do
        local free = Core.freeAt(e)
        if now < free then out[#out + 1] = { t = e.t, zone = e.zone, free = free, synthetic = e.synthetic, ref = e } end
    end
    table.sort(out, function(a, b) return a.t < b.t end)
    return out
end

-- "23m", "1m 05s" style countdown
function Core.countdown(seconds)
    seconds = math.max(0, math.floor(seconds))
    local m, s = math.floor(seconds / 60), seconds % 60
    if m >= 10 then return ("%dm"):format(m) end
    if m >= 1 then return ("%dm %02ds"):format(m, s) end
    return ("%ds"):format(s)
end

-- Locale-proof pattern from a client format string ("%s has been reset.").
function Core.pattern(fmt)
    local p = fmt:gsub("([%(%)%.%[%]%*%+%-%?%^%$])", "%%%1")
    p = p:gsub("%%s", "(.+)"):gsub("%%d", "(%%d+)")
    return "^" .. p .. "$"
end

-- WoW has no `os` library, only the global `date`; LuaJIT (tests) only has os.date.
local fmtDate = date or (os and os.date)
function Core.clockTime(epoch)
    return fmtDate("%H:%M", epoch)
end

return Core
