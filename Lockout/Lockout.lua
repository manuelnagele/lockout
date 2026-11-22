-- Lockout: instance entries in the rolling hour (5) and day (30), per character.
-- Public API for other addons: Lockout.Status() -> see Core.status. A Deadbeat module (spec 2.0).
local ADDON, ns = ...
local Core = ns.Core
local VERSION = "1.0.1"

local db, char
local current          -- zone name of the instance we're in, or nil
local active           -- the entry for the instance we're in: its .seen follows us while inside
local resetPatterns = {}
local tooMany = {}
local line             -- own text line, only without Deadbeat
local badge            -- Deadbeat widget: five diamonds, lit = free this hour
local nextItem         -- Deadbeat item: the countdown to the next free slot (with 1 or 0 left)
local PIPS, PIP = 5, 7

Lockout = {}

local function print_(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffd8a446Lockout|r: " .. msg)
end

local function now()
    return GetServerTime and GetServerTime() or time()
end

function Lockout.Status(c)
    c = c or char
    if not c then return nil end
    c.entries = Core.prune(c.entries or {}, now())
    return Core.status(c.entries, now())
end

local function label(c)
    return ("%s %s"):format(c.name or "?", c.level and tostring(c.level) or "")
end

-- Whose slots matter right now: yours if you've entered anything this hour, else the character that was in an
-- instance most recently (on the bank alt: your main, whose next login needs a free slot).
local function watched()
    if not char then return nil end
    local t = now()
    if #Core.held(char.entries, t) > 0 then return char, false end
    local best, latest
    for _, c in pairs(db.chars) do
        if c ~= char then
            for _, e in ipairs(c.entries or {}) do
                if t < Core.freeAt(e) and (not latest or e.t > latest) then best, latest = c, e.t end
            end
        end
    end
    if best then return best, true end
    return char, false
end

-- "3/5", coloured: green 3-5 left, yellow 1-2, red 0; plus the next free time when it matters.
function Lockout.Text()
    local s = Lockout.Status()
    if not s then return "" end
    local color = s.hourLeft >= 3 and "7fd17f" or (s.hourLeft >= 1 and "ffd100" or "ff4040")
    local text = ("|cff%s%d/%d|r"):format(color, s.hourLeft, Core.PER_HOUR)
    if s.hourLeft <= 2 and s.nextFree then
        text = text .. (" |cffaaaaaa%s%s|r"):format(s.estimated and "~" or "", Core.clockTime(s.nextFree))
    end
    if s.dayUsed >= 25 then text = text .. (" |cffaaaaaa%d/day|r"):format(s.dayLeft) end
    return text
end

local function drawPips()
    local who, other = watched()
    local s = Lockout.Status(who)
    if not badge or not s then return end
    local K = Deadbeat.kit
    local P = K.P
    local now = GetServerTime and GetServerTime() or time()
    for i, pip in ipairs(badge.pips) do
        local c = (s.hourLeft == 0 or s.dayLeft == 0) and K.RED or (i <= s.hourLeft and P.goldOn or P.bronze1)
        pip:SetVertexColor(c[1], c[2], c[3], 1)
        pip.glow:Stop()
    end
    -- with 1 or 0 left (or while watching another character): the countdown to the next free slot, as an item
    if nextItem then
        if s.dayLeft == 0 and s.dayFree then              -- the day's 30 are used: that wait is the one that counts
            nextItem:Set("day " .. Core.countdown(s.dayFree - now), "bad")
            nextItem:Show()
        elseif (s.hourLeft <= 1 or other) and s.nextFree then
            nextItem:Set((s.estimated and "~" or "") .. Core.countdown(s.nextFree - now), s.hourLeft == 0 and "bad" or "warn")
            nextItem:Show()
        else
            nextItem:Hide()
        end
    end
    -- the slot that frees up next breathes in its last 5 minutes
    if s.nextFree and s.nextFree - now <= 300 and s.hourLeft < PIPS then
        local next = badge.pips[s.hourLeft + 1]
        next:SetVertexColor(P.bronze4[1], P.bronze4[2], P.bronze4[3], 1)
        next.glow:Play()
    end
end

-- --- the big indicator: on a character waiting for another (the bank alt), green = a slot is free, red = wait ---

local big
local wasFree

local function buildBig()
    local K = Deadbeat.kit
    local P = K.P
    big = CreateFrame("Frame", "LockoutBig", UIParent)
    big:SetSize(300, 86)
    local p = db.big
    if p then big:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else big:SetPoint("CENTER", UIParent, "CENTER", 0, 160) end
    big:SetMovable(true)
    big:EnableMouse(true)
    big:SetClampedToScreen(true)
    big:RegisterForDrag("LeftButton")
    big:SetScript("OnDragStart", function(self) if IsShiftKeyDown() then self:StartMoving() end end)
    big:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, rel, x, y = self:GetPoint()
        db.big = { point, rel, x, y }
    end)
    K.ground(big, 0.92)
    big.fill = big:CreateTexture(nil, "BORDER")
    big.fill:SetPoint("TOPLEFT", 3, -3)
    big.fill:SetPoint("BOTTOMRIGHT", -3, 3)
    big.fill:SetTexture(K.barTexture())
    K.border(big, false)
    big.title = K.text(big, "GameFontNormalHuge")
    big.title:SetPoint("TOP", 0, -14)
    big.sub = K.text(big, "GameFontHighlight", { 1, 1, 1 })
    big.sub:SetPoint("BOTTOM", 0, 14)
    big.flash = K.flash(big.fill, big)
    big:Hide()
end

local function drawBig()
    if not Deadbeat or db.bigOff then if big then big:Hide() end return end
    local who, other = watched()
    if not other then if big then big:Hide() end wasFree = nil return end
    if not big then buildBig() end
    local K = Deadbeat.kit
    local s = Lockout.Status(who)
    local t = now()
    -- free only if both the hour (5) and the day (30) allow another entry
    local free, at, why = Core.verdict(s)
    local c = free and K.GREEN or K.RED
    big.fill:SetVertexColor(c[1], c[2], c[3], 0.55)
    if free then
        big.title:SetText("|cffffffffINSTANCE FREE|r")
        big.sub:SetText(("%s  ·  %d of %d free"):format(label(who), s.hourLeft, PIPS))
    elseif why == "day" then
        big.title:SetText(("|cffffffffDAILY LIMIT  %s|r"):format(at and Core.countdown(at - t) or ""))
        big.sub:SetText(("%s  ·  %d today  ·  frees at %s"):format(label(who), s.dayUsed, at and Core.clockTime(at) or "?"))
    else
        big.title:SetText(("|cffffffffWAIT  %s%s|r"):format(s.estimated and "~" or "", Core.countdown(at - t)))
        big.sub:SetText(("%s  ·  frees at %s"):format(label(who), Core.clockTime(at)))
    end
    if free and wasFree == false then
        big.flash:Stop() big.flash:Play()
        local loaded = C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Catch")
        if loaded then pcall(PlaySoundFile, "Interface\\AddOns\\Catch\\Sounds\\window_pluck.ogg", "SFX")
        else pcall(PlaySound, SOUNDKIT and SOUNDKIT.MAP_PING or 3175, "SFX") end
    end
    wasFree = free
    big:Show()
end

local function refresh()
    if active then active.seen = now() end
    if line then line.text:SetText("Instances " .. Lockout.Text()) end
    drawPips()
    drawBig()
end

-- --- entries -------------------------------------------------------------------

local pending          -- {zone, map, t, counted, entry, prev}: an entry waiting for its first mob

local function announce()
    local s = Lockout.Status()
    if s.dayLeft == 0 then
        print_(("no instances left today (30) — the next frees at %s."):format(s.dayFree and Core.clockTime(s.dayFree) or "?"))
    elseif s.hourLeft == 1 then
        print_("one instance left this hour.")
    elseif s.hourLeft == 0 then
        print_(("no instances left — next one free at %s."):format(Core.clockTime(s.nextFree)))
    end
end

local function latest(zone)
    for i = #char.entries, 1, -1 do
        if char.entries[i].zone == zone then return char.entries[i] end
    end
end

local function removeEntry(entry)
    for i = #char.entries, 1, -1 do
        if char.entries[i] == entry then table.remove(char.entries, i) return end
    end
end

-- Provisional decision on entry (reset message, relog, 30 min); the first mob's instance copy settles it.
local function entered(zone, map)
    local t = now()
    local last = char.last[zone]
    local counted = Core.isNewEntry(last, t, char.loginAt)
    local entry
    if counted then
        entry = { t = t, seen = t, zone = zone }
        char.entries[#char.entries + 1] = entry
    end
    active = entry or latest(zone)
    pending = { zone = zone, map = map, t = t, counted = counted, entry = entry, prev = last and last.copy }
    char.last[zone] = { at = t, copy = last and last.copy }
    current = zone
    if counted then announce() end
    refresh()
end

local function sawUnit(unit)
    if not pending or not char then return end
    local guid = UnitGUID(unit)
    if not guid or (issecretvalue and issecretvalue(guid)) then return end
    local map, copy = Core.instanceCopy(guid)
    if not copy or (pending.map and map ~= pending.map) then return end
    local verdict = Core.confirm(pending.counted, pending.prev, copy)
    if verdict == "remove" then
        removeEntry(pending.entry)
        active = latest(pending.zone)
    elseif verdict == "add" then
        active = { t = pending.t, seen = now(), zone = pending.zone, copy = copy }
        char.entries[#char.entries + 1] = active
        announce()
    elseif pending.entry then
        pending.entry.copy = copy
    end
    char.last[pending.zone].copy = copy
    char.lastVerdict = verdict
    pending = nil
    refresh()
end

local function left()
    if current and char.last[current] then char.last[current].leftAt = now() end
    if active then active.seen = now() end
    current, pending, active = nil, nil, nil
end

local function checkInstance()
    if not char then return end
    local inInstance, kind = IsInInstance()
    if inInstance and (kind == "party" or kind == "raid") then
        local zone, _, _, _, _, _, _, map = GetInstanceInfo()
        if zone ~= current then
            if current then left() end
            entered(zone, map)
        end
    elseif current then
        left()
    end
    refresh()
end

local function onSystem(msg)
    if not char or (issecretvalue and issecretvalue(msg)) then return end
    for _, p in ipairs(resetPatterns) do
        local zone = msg:match(p)
        if zone then
            local t = now()
            if char.last[zone] then char.last[zone].resetAt = t end
            -- on the bank alt: the main's instance ends now (the slot frees an hour from here)
            local best
            for _, c in pairs(db.chars) do
                for _, e in ipairs(c.entries or {}) do
                    if e.zone == zone and t - e.t < 2 * Core.HOUR and (not best or e.t > best.t) then best = e end
                end
            end
            if best and best ~= active then best.seen = math.max(best.seen or best.t, t) end
            refresh()
            return
        end
    end
    for _, text in ipairs(tooMany) do
        if msg == text or msg:lower():find("too many instances", 1, true) then
            local added = Core.calibrate(char.entries, now())
            if added > 0 then print_(("the game says the limit is reached — counted %d entries I missed."):format(added)) end
            refresh()
            return
        end
    end
end

-- --- frames & events ---------------------------------------------------------------

local function charLines(tip, c, title)
    local st = Lockout.Status(c)
    if not st then return end
    local K = Deadbeat.kit
    local g = K.P.warmGrey
    local t = now()
    local col = st.hourLeft == 0 and K.RED or K.P.goldOn
    local right = ("|cff%s%d|r of %d free"):format(K.hex(col), st.hourLeft, PIPS)
    if st.nextFree and st.hourLeft < PIPS then
        right = right .. ("  ·  next %s%s  (in %s)"):format(st.estimated and "~" or "", Core.clockTime(st.nextFree),
            Core.countdown(st.nextFree - t))
    end
    tip:AddDoubleLine(title, right, g[1], g[2], g[3], 1, 1, 1)
    for _, e in ipairs(Core.held(c.entries, t)) do
        tip:AddDoubleLine(("   %s  %s%s"):format(Core.clockTime(e.t), e.zone or "?", e.synthetic and " (estimated)" or ""),
            ("frees %s  ·  in %s"):format(Core.clockTime(e.free), Core.countdown(e.free - t)),
            g[1], g[2], g[3], g[1], g[2], g[3])
    end
    if st.dayLeft <= 5 then tip:AddDoubleLine(" ", st.dayLeft .. " left today", 1, 1, 1, K.RED[1], K.RED[2], K.RED[3]) end
end

local function section(tip)
    if not char then return end
    charLines(tip, char, "  This character")
    local t = now()
    for _, c in pairs(db.chars) do
        if c ~= char and #Core.held(c.entries or {}, t) > 0 then charLines(tip, c, "  " .. label(c)) end
    end
end

local function buildDisplay()
    if Deadbeat and Deadbeat.SPEC and Deadbeat.SPEC >= "2.0" then
        local icon = "Interface\\Icons\\INV_Misc_PocketWatch_01"
        local m = Deadbeat.Register("Lockout", { icon = icon, spec = "2.0" })
        local places = { farm = true, dungeon = true, city = true, world = true }   -- raids have weekly lockouts
        m:Options({ title = "Lockout", icon = icon, rows = {
            { kind = "header", label = "Instance lockouts" },
            { kind = "toggle", label = "Big green/red indicator", get = function() return not db.bigOff end,
              set = function(on) db.bigOff = not on refresh() end },
            { kind = "note", label = "Shift-drag the big indicator to move it. Clicking the diamonds shows or hides it too." },
            { kind = "button", label = "Forget this character's lockouts", text = "Clear", confirm = true,
              run = function() SlashCmdList.LOCKOUT("clear") end },
        } })
        badge = m:Widget("slots", { name = "Slots this hour", width = PIPS * (PIP + 4), contexts = places })
        badge.pips = {}
        for i = 1, PIPS do
            local pip = badge:CreateTexture(nil, "ARTWORK")
            pip:SetTexture("Interface\\Buttons\\WHITE8x8")
            pip:SetSize(PIP, PIP)
            pip:SetRotation(math.pi / 4)
            pip:SetPoint("RIGHT", badge, "RIGHT", -((PIPS - i) * (PIP + 4)) - 2, 0)
            local glow = pip:CreateAnimationGroup()
            glow:SetLooping("BOUNCE")
            local a = glow:CreateAnimation("Alpha")
            a:SetFromAlpha(1) a:SetToAlpha(0.35) a:SetDuration(0.9) a:SetSmoothing("IN_OUT")
            pip.glow = glow
            badge.pips[i] = pip
        end
        nextItem = m:Item("next", { name = "Next free slot", icon = icon, contexts = places })
        m:Tooltip(function(tip) section(tip) end)
        m:Click(function() db.bigOff = not db.bigOff refresh() end,
            function() return db.bigOff and "show the big indicator" or "hide the big indicator" end)
        return
    end
    line = CreateFrame("Frame", "LockoutLine", UIParent)
    line:SetSize(120, 16)
    line:SetPoint("TOP", Minimap, "BOTTOM", 0, -48)
    line.text = line:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line.text:SetPoint("CENTER")
end

local f = CreateFrame("Frame")
local handlers = {}

function handlers.ADDON_LOADED(name)
    if name ~= ADDON then return end
    LockoutDB = LockoutDB or {}
    db = LockoutDB
    db.version, db.chars = VERSION, db.chars or {}
end

function handlers.PLAYER_LOGIN()
    local guid = UnitGUID("player")
    db.chars[guid] = db.chars[guid] or { entries = {}, last = {} }
    char = db.chars[guid]
    char.name = UnitName("player")
    char.level = UnitLevel and UnitLevel("player") or nil
    local logins = {}
    for _, c in pairs(db.chars) do if c.loginAt then logins[#logins + 1] = c.loginAt end end
    for _, c in pairs(db.chars) do Core.backfill(c.entries or {}, logins, now()) end
    for _, key in ipairs({ "INSTANCE_RESET_SUCCESS" }) do
        if _G[key] then resetPatterns[#resetPatterns + 1] = Core.pattern(_G[key]) end
    end
    for _, key in ipairs({ "TRANSFER_ABORT_TOO_MANY_INSTANCES", "ERR_TOO_MANY_INSTANCES" }) do
        if _G[key] then tooMany[#tooMany + 1] = _G[key] end
    end
    if #tooMany == 0 then tooMany[1] = "You have entered too many instances recently." end
    buildDisplay()
    refresh()
    C_Timer.NewTicker(1, refresh)   -- the countdown ticks every second
end

handlers.PLAYER_ENTERING_WORLD = function(isInitialLogin)
    if isInitialLogin and char then char.loginAt = now() end  -- a relog, not a /reload
    checkInstance()
end
handlers.ZONE_CHANGED_NEW_AREA = function() checkInstance() end
handlers.CHAT_MSG_SYSTEM = onSystem

-- Logging out inside a dungeon to reset it (bank-alt relog): the next login needs a free slot, or you land outside.
function handlers.PLAYER_CAMPING()
    if not char or not current then return end
    local st = Lockout.Status()
    if not st or (st.hourLeft > 1 and st.dayLeft > 1) then return end
    local msg
    local free, at, why = Core.verdict(st)
    if not free then
        msg = ("Lockout: no free instance %suntil %s (in %s) — a reset now puts you outside"):format(
            why == "day" and "today, " or "", Core.clockTime(at), Core.countdown(at - now()))
    elseif st.dayLeft == 1 then
        msg = "Lockout: the last instance of the day (30) — after this reset you can't enter again today"
    else
        msg = ("Lockout: last free instance — after this reset, the next frees at %s"):format(Core.clockTime(st.nextFree))
    end
    if RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, msg, not free and { r = 1, g = 0.35, b = 0.3 } or { r = 1, g = 0.82, b = 0.25 })
    end
    print_(msg)
    if not free then pcall(PlaySound, SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master") end
end
handlers.NAME_PLATE_UNIT_ADDED = sawUnit
handlers.UPDATE_MOUSEOVER_UNIT = function() sawUnit("mouseover") end
handlers.PLAYER_TARGET_CHANGED = function() sawUnit("target") end
handlers.UI_ERROR_MESSAGE = function(_, msg) if msg then onSystem(msg) end end

f:SetScript("OnEvent", function(_, event, ...) handlers[event](...) end)
for event in pairs(handlers) do pcall(f.RegisterEvent, f, event) end

SLASH_LOCKOUT1 = "/lockout"
SlashCmdList.LOCKOUT = function(msg)
    local cmd = strtrim(msg or ""):lower()
    local s = Lockout.Status()
    if cmd == "debug" then
        print_(("v%s · reset patterns %d · too-many strings %d · in %s · %s"):format(VERSION, #resetPatterns,
            #tooMany, current or "no instance", Lockout.Text()))
        local last = current and char.last[current]
        print_(("instance copy: %s · waiting for a mob: %s · last verdict: %s"):format(
            tostring(last and last.copy), tostring(pending ~= nil), tostring(char.lastVerdict)))
        local guid = UnitGUID("target")
        if guid then print_("target guid: " .. ((issecretvalue and issecretvalue(guid)) and "<secret>" or guid)) end
        for _, t in ipairs(tooMany) do print_("  too many: " .. t) end
        return
    end
    if cmd == "big" then
        db.bigOff = not db.bigOff
        print_("big indicator " .. (db.bigOff and "off." or "on."))
        refresh()
        return
    end
    if cmd == "clear" then
        char.entries, char.last = {}, {}
        print_("cleared.")
        refresh()
        return
    end
    print_(("%d of %d left this hour, %d of %d today."):format(s.hourLeft, Core.PER_HOUR, s.dayLeft, Core.PER_DAY))
    local t = now()
    for _, e in ipairs(Core.held(char.entries, t)) do
        print_(("  %s %s · frees %s%s"):format(Core.clockTime(e.t), e.zone, Core.clockTime(e.free),
            e.synthetic and " (estimated)" or ""))
    end
end
