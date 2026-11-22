-- luajit tests/smoke.lua: Lockout on Deadbeat (sibling repo) against the shared WoW stub.
local W = dofile("../deadbeat/tests/wowstub.lua")
local dns = {}
for _, f in ipairs({ "../deadbeat/Deadbeat/Kit.lua", "../deadbeat/Deadbeat/Deadbeat.lua", "../deadbeat/Deadbeat/Settings.lua" }) do assert(loadfile(f))("Deadbeat", dns) end
W.frames[#W.frames]:_fire("ADDON_LOADED", "Deadbeat")
W.frames[#W.frames]:_fire("PLAYER_LOGIN")
function GetServerTime() return os.time() end
function UnitName() return "Hero" end
function UnitLevel() return 60 end
function IsInInstance() return false, "none" end
INSTANCE_RESET_SUCCESS = "%s has been reset."
local ns = {}
for _, f in ipairs({ "Lockout/Core.lua", "Lockout/Lockout.lua" }) do assert(loadfile(f))("Lockout", ns) end
local ev = W.frames[#W.frames]
ev:_fire("ADDON_LOADED", "Lockout")
ev:_fire("PLAYER_LOGIN")
ev:_fire("PLAYER_ENTERING_WORLD", true)
for _, t in ipairs(W.tickers) do t() end
DeadbeatBar:_script("OnEnter")
local joined = table.concat(W.tipLines, "\n")
assert(joined:find("Instances"), "Lockout's tooltip section: " .. joined)
-- logging out inside a dungeon with no slot left: a warning
function IsInInstance() return true, "party" end
function GetInstanceInfo() return "Maraudon", "party", 1, "", 5, 0, false, 349 end
ev:_fire("PLAYER_ENTERING_WORLD", false)
for i = 1, 6 do LockoutDB.chars["Player-1-ABC"].entries[#LockoutDB.chars["Player-1-ABC"].entries + 1] = { t = os.time() - i * 60, zone = "Maraudon" } end
local warned
RaidWarningFrame = {}
function RaidNotice_AddMessage(_, msg) warned = msg end
function PlaySound() end
ev:_fire("PLAYER_CAMPING")
assert(warned and warned:find("no free instance"), "logout warning: " .. tostring(warned))
for _, t in ipairs(W.tickers) do t() end
DeadbeatBar:_script("OnEnter")
assert(select(2, table.concat(W.tipLines, "\n"):gsub("Maraudon", "")) >= 5, "one tooltip line per held entry")
-- on the bank alt: the main's slots
LockoutDB.chars["Player-1-BANK"] = { entries = {}, last = {}, name = "Hero", level = 1 }
local main = LockoutDB.chars["Player-1-ABC"]
LockoutDB.chars["Player-1-ABC"] = nil
LockoutDB.chars["Player-1-MAIN"] = main
function UnitGUID() return "Player-1-BANK" end
function UnitLevel() return 1 end
function IsInInstance() return false, "none" end
ev:_fire("PLAYER_LOGIN")
for _, t in ipairs(W.tickers) do t() end
DeadbeatBar:_script("OnEnter")
assert(table.concat(W.tipLines, "\n"):find("Instances · Hero 60"), "the main's slots on the alt: " .. table.concat(W.tipLines, " | "))
assert(LockoutBig, "big indicator on the alt")
SlashCmdList.LOCKOUT("big")
SlashCmdList.LOCKOUT("big")
SlashCmdList.LOCKOUT("debug")
print("lockout smoke ok")
