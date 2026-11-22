-- luajit tests/smoke.lua: Lockout on Deadbeat (sibling repo) on the shared harness (deadbeat-spec).
local W = dofile(os.getenv("HARNESS") or "../deadbeat-spec/harness/wowstub.lua")   -- the shared harness
W.loadDeadbeat(os.getenv("DEADBEAT") or "../deadbeat")
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
local function item(id) for _, it in ipairs(Deadbeat.Items()) do if it.key == "Lockout." .. id then return it end end end
assert(item("slots") and item("slots").kind == "widget", "the diamonds are a widget item")
assert(item("next") and not item("next").wanted, "no countdown with 5 slots free")
local joined = W.tooltip(item("slots"))
assert(joined:find("This character"), "Lockout's tooltip: " .. joined)
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
assert(item("next").wanted and item("next").state == "bad", "0 free: the countdown item, red: " .. tostring(item("next").value))
assert(select(2, W.tooltip(item("slots")):gsub("Maraudon", "")) >= 5, "one tooltip line per held entry")
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
assert(W.tooltip(item("slots")):find("Hero 60"), "the main's slots on the alt: " .. table.concat(W.tipLines, " | "))
item("slots").frame:_script("OnClick", "LeftButton")
assert(LockoutDB.bigOff, "clicking the diamonds hides the big indicator")
item("slots").frame:_script("OnClick", "LeftButton")
assert(LockoutBig, "big indicator on the alt")
SlashCmdList.LOCKOUT("big")
SlashCmdList.LOCKOUT("big")
SlashCmdList.LOCKOUT("debug")
print("lockout smoke ok")
