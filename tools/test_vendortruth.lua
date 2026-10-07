--[[ test_vendortruth.lua -- run from the AddOns directory:
       lua VendorTruth/tools/test_vendortruth.lua

     Deliberately run against the REAL data rather than fixtures: the actual
     ShaguTweaks price table and the actual prices SellValue recorded at
     vendors on this server. Fixtures would prove the code does what it was
     written to do; these prove it does the thing that was worth doing, on the
     numbers that caused the problem.

     The items named below are real ones, picked because they are the shape of
     the failure: an item the static table values at nearly nineteen gold that
     no vendor here will buy, and one it overstates by six gold. ]]

local failures, checks = 0, 0
local function check(label, got, want)
    checks = checks + 1
    if got ~= want then
        failures = failures + 1
        print("  FAIL " .. label .. ": got " .. tostring(got) ..
            ", wanted " .. tostring(want))
    end
end

-- ------------------------------------------------------------------ stubs
local function noop() end
local anything = setmetatable({}, { __index = function() return noop end })

local function freshWorld()
    _G = _G or {}
    DEFAULT_CHAT_FRAME = { AddMessage = noop }
    SlashCmdList = {}
    GameTooltip = setmetatable({ AddLine = noop, Show = noop },
                               { __index = function() return noop end })
    CreateFrame = function()
        return setmetatable({}, { __index = function() return noop end })
    end
    GetAuctionItemLink = function() return nil end
    -- 1.12 has math.mod, not the % operator.
    math.mod = math.mod or function(a, b) return a - math.floor(a / b) * b end
    table.getn = table.getn or function(t) return #t end
    -- 1.12 has string.gfind; 5.4 renamed it gmatch. The addon is right for the
    -- client it runs on, so the harness adapts rather than the addon.
    string.gfind = string.gfind or string.gmatch

    ShaguTweaks = setmetatable({
        GetGlobalEnv = function() return _G end,
        T = anything,
        GetExpansion = function() return "vanilla" end,
        GetItemLinkByName = noop,
        GetItemIDFromLink = noop,
        RegisterModule = noop,
    }, { __index = function() return noop end })
end

--[[ The real static table.

     The file is run for its data and is expected to fail afterwards: its last
     act is to register itself as a ShaguTweaks module, which needs the real
     addon. SellValueDB is assigned well before that, so the error is after the
     part we came for -- what matters is whether the table exists, not whether
     the chunk finished. ]]
local function loadStaticDB()
    local chunk = loadfile("ShaguTweaks/mods/vendor-values.lua")
    if not chunk then return nil end
    pcall(chunk)
    local db = ShaguTweaks.SellValueDB
    if type(db) ~= "table" then return nil end
    return db
end

--- The real prices recorded at vendors on this server.
local function loadLearned()
    local paths = {
        "../../WTF/Account/SALAHAJA/SavedVariables/SellValue.lua",
        "../../WTF/Account/SALAMAHI/SavedVariables/SellValue.lua",
    }
    local merged = {}
    for i = 1, table.getn(paths) do
        SellValues = nil
        local chunk = loadfile(paths[i])
        if chunk then
            pcall(chunk)
            if type(SellValues) == "table" then
                for k, v in pairs(SellValues) do
                    --[[ A zero is a fact -- "the vendor refused it" -- so it
                         must not be overwritten by another account that simply
                         has no entry. Only a real price displaces one. ]]
                    if merged[k] == nil or (v and v > 0) then merged[k] = v end
                end
            end
        end
    end
    return merged
end

print("\nVendorTruth: against the real price tables\n")

freshWorld()
local db = loadStaticDB()
if not db then
    print("  !! could not load ShaguTweaks/mods/vendor-values.lua")
    os.exit(1)
end
local learned = loadLearned()
local learnedCount = 0
for _ in pairs(learned) do learnedCount = learnedCount + 1 end
if learnedCount == 0 then
    print("  !! no SellValue data found; run this from the AddOns directory")
    os.exit(1)
end

--[[ The state of things BEFORE, captured so the test proves a change rather
     than merely agreeing with the end result. ]]
local TRAP = 21563      -- static table: 18g88s88c. This server: unsellable.
local OVER = 21522      -- static table: 14g22s69c. This server: 7g97s48c.
local trapBefore = db[TRAP]
local overBefore = db[OVER]
check("the trap item starts out priced like treasure", trapBefore > 180000, true)
check("and the overstated one starts high", overBefore > 140000, true)

SellValues = learned
dofile("VendorTruth/VendorTruth.lua")
check("it applies against real data", VendorTruth.Apply(), true)

----------------------------------------------------------------------
-- the traps
----------------------------------------------------------------------
--[[ The failure worth preventing. An item the table calls eighteen gold looks
     like the best flip on the auction house, and the vendor will not take it.
     Nothing in the game warns you; you simply own it. ]]
check("an item vendors here refuse is now priced at nothing", db[TRAP], 0)
check("and is known to be unsellable", VendorTruth.Check(TRAP).sellable, false)
check("from having actually been tried here", VendorTruth.Check(TRAP).verified, true)
check("more than a hundred such traps were defused",
    VendorTruth.stats.traps > 100, true)

----------------------------------------------------------------------
-- the overstatements
----------------------------------------------------------------------
check("an overstated price is brought down to what is paid here",
    db[OVER] < overBefore, true)
check("to the figure a vendor here actually quoted", db[OVER], 79748)
check("which is a real correction, not a rounding",
    overBefore - db[OVER] > 60000, true)

----------------------------------------------------------------------
-- what it must NOT do
----------------------------------------------------------------------
--[[ Items nobody has sold here keep the static price. Inventing one would be
     the same mistake in the other direction. ]]
local untouched, sample = 0, nil
for id, price in pairs(db) do
    if not VendorTruth.verified[id] and price and price > 0 then
        untouched = untouched + 1
        if not sample then sample = id end
    end
end
check("items never sold here keep their static price", untouched > 1000, true)
check("and are reported as unverified",
    VendorTruth.Check(sample).verified, false)
--[[ The reported figure and the flagged figure must be the same figure, or
     the report is describing a different set from the one the tooltips warn
     about. ]]
check("the count reported is exactly the set that gets flagged",
    VendorTruth.stats.unverified, untouched)

--[[ Only the unverified get a tooltip warning. If every item carried one it
     would be noise, and noise is read as decoration. ]]
local warned = {}
local tip = { AddLine = function(_, text) table.insert(warned, text) end, Show = noop }
VendorTruth.DecorateTooltip(tip, "item:" .. sample)
check("an unverified item is flagged on its tooltip", table.getn(warned), 1)
warned = {}
VendorTruth.DecorateTooltip(tip, "item:" .. OVER)
check("a verified one is not", table.getn(warned), 0)
warned = {}
VendorTruth.DecorateTooltip(tip, "item:" .. TRAP)
check("nor is one already known to be worthless", table.getn(warned), 0)

----------------------------------------------------------------------
-- refusing safely
----------------------------------------------------------------------
--[[ Both halves are somebody else's addon. Missing either means no correction
     is possible, and saying so is the only honest option -- silently doing
     nothing would leave the player believing their prices were fixed. ]]
freshWorld()
SellValues = nil
check("with no recorded prices it declines", VendorTruth.Apply(), false)
check("and says why", string.find(VendorTruth.reason or "", "SellValue") ~= nil, true)

freshWorld()
SellValues = { ["item:1"] = 10 }
ShaguTweaks = nil
check("with no table to correct it declines", VendorTruth.Apply(), false)
check("and says why", string.find(VendorTruth.reason or "", "ShaguTweaks") ~= nil, true)

----------------------------------------------------------------------
-- the arithmetic
----------------------------------------------------------------------
--[[ SellValue divides a stack's total by its size, so a price can arrive
     fractional. Rounded DOWN on purpose: understating costs a missed flip,
     overstating costs gold, and this addon exists because of the latter. ]]
freshWorld()
ShaguTweaks.SellValueDB = { [50] = 999 }
SellValues = { ["item:50"] = 12.9 }
VendorTruth.verified = {}
VendorTruth.Apply()
check("a fractional price is rounded down, never up",
    ShaguTweaks.SellValueDB[50], 12)
check("money formats as gold/silver/copper", VendorTruth.Money(79748), "7g97s48c")
check("and small amounts stay small", VendorTruth.Money(5), "5c")

----------------------------------------------------------------------
-- the watchlist, against aux's real scan history
----------------------------------------------------------------------
--[[ aux records the lowest buyout it saw for every item it has ever scanned,
     as "next_push#daily_min_buyout#value@time;...". The first field is a
     TIMESTAMP, not a price -- around 1.79 billion. Read it as money and every
     item on the auction house looks like a hundred and seventy thousand gold
     of profit, which is the one parsing mistake here that would be both
     catastrophic and entirely plausible-looking. ]]
freshWorld()
local staticDB = loadStaticDB()
SellValues = loadLearned()
VendorTruth.verified = {}
VendorTruth.Apply()

aux = nil
local chunk = loadfile("../../WTF/Account/SALAHAJA/SavedVariables/aux-addon.lua")
if chunk then pcall(chunk) end
if type(aux) == "table" and aux.faction then
    for _, data in pairs(aux.faction) do
        if type(data) == "table" and type(data.history) == "table" then
            aux.faction_data = data
        end
    end
end

if not (aux and aux.faction_data) then
    print("  (skipped: no aux history found for this account)")
else
    local lowest = VendorTruth.LowestSeen()
    local seen = 0
    for _ in pairs(lowest) do seen = seen + 1 end
    check("aux's history is readable", seen > 1000, true)

    --[[ The timestamp guard. Every recorded price must be a plausible auction
         price; a value in the billions means field one was read as money. ]]
    local absurd = 0
    for _, price in pairs(lowest) do
        if price > 100000000 then absurd = absurd + 1 end   -- over 10,000 gold
        if price <= 0 then absurd = absurd + 1 end
    end
    check("no timestamp was mistaken for a price", absurd, 0)

    local list = VendorTruth.Watchlist()
    check("a watchlist comes back", list ~= nil, true)
    check("and it is short, because the opportunity is", table.getn(list) < 500, true)
    check("but not empty", table.getn(list) > 0, true)

    --[[ Sorted best first: the list is there to be acted on from the top, and
         the margins are small enough that order is most of its value. ]]
    local ordered = true
    for i = 2, table.getn(list) do
        if list[i].margin > list[i - 1].margin then ordered = false end
    end
    check("sorted by margin, best first", ordered, true)

    local every_profitable, every_verified = true, true
    for i = 1, table.getn(list) do
        if list[i].margin <= 0 then every_profitable = false end
        if not list[i].verified then every_verified = false end
    end
    check("every entry is actually profitable", every_profitable, true)
    --[[ Guesses are excluded by default. A margin of a few silver cannot
         absorb one wrong vendor price, so the default is the safe set. ]]
    check("and every price is one confirmed here", every_verified, true)

    local loose = VendorTruth.Watchlist(true)
    check("asking for guesses too gives at least as many",
        table.getn(loose) >= table.getn(list), true)
end

----------------------------------------------------------------------
-- the parsing, on a record whose answer is known
----------------------------------------------------------------------
freshWorld()
ShaguTweaks.SellValueDB = { [9837] = 5000, [6603] = 30000 }
SellValues = { ["item:9837"] = 5000, ["item:6603"] = 30000 }
VendorTruth.verified = {}
VendorTruth.Apply()
aux = { faction_data = { history = {
    -- lowest here is 2200 (today), not the 1789531200 timestamp beside it
    ["9837:1552"] = "1789531200#2200#3500@1788580800",
    -- lowest here is 6500, from the stored days rather than today's 24999
    ["6603:255"]  = "1789963200#24999#6500@1789358400;10000@1788580800",
} } }
local low = VendorTruth.LowestSeen()
check("today's figure is used when it is the lowest", low[9837], 2200)
check("an older day wins when it was cheaper", low[6603], 6500)

local wl = VendorTruth.Watchlist()
check("both show up as opportunities", table.getn(wl), 2)
check("the bigger margin leads", wl[1].id, 6603)
check("with the right margin", wl[1].margin, 30000 - 6500)

--[[ An item listed ABOVE vendor is not an opportunity and must not appear,
     however much history it has. ]]
aux.faction_data.history["9837:1552"] = "1789531200#99999#99999@1788580800"
wl = VendorTruth.Watchlist()
check("an item that never went below vendor is left out", table.getn(wl), 1)

----------------------------------------------------------------------
-- sharing a scan between accounts
----------------------------------------------------------------------
--[[ SavedVariables cannot cross accounts -- the account name is in the path --
     so this goes through Nampower's CustomData, which belongs to the
     installation. Scan on the bank alt, and the main on the other account has
     the prices without opening the auction house.

     Scoped by REALM, not faction: this server runs one auction house for both,
     so a Horde scan is just as true for an Alliance character. ]]
local FOLDER = {}
local function withFiles()
    WriteCustomFile = function(name, text) FOLDER[name] = text end
    ReadCustomFile = function(name) return FOLDER[name] end
end

--[[ Rewriting one field of aux's record without disturbing the rest. The
     awkward shape is a record with no stored days yet -- it ends in a bare
     separator, and a careless rewrite silently drops it, which changes what
     aux parses back. ]]
freshWorld()
withFiles()
check("a full record keeps its stored days",
    VendorTruth.WithDailyMin("1789531200#2200#3500@1788580800", 1000),
    "1789531200#1000#3500@1788580800")
check("a record with no stored days keeps its trailing separator",
    VendorTruth.WithDailyMin("1789531200#2200#", 1000),
    "1789531200#1000#")
check("several stored days survive intact",
    VendorTruth.WithDailyMin("1#2#3@4;5@6", 9), "1#9#3@4;5@6")
check("the timestamp is never the field that changes",
    VendorTruth.DailyMin("1789531200#2200#"), 2200)

----------------------------------------------------------------------
-- the round trip
----------------------------------------------------------------------
GetRealmName = function() return "N'Zoth" end
UnitFactionGroup = function() return "Horde" end     -- the scanner
aux = { faction_data = { history = {
    ["100:0"] = "1789531200#5000#",
    ["200:0"] = "1789531200#7000#9000@1788580800",
} } }
local wrote = VendorTruth.ShareScan()
check("the scan is written out", wrote, 2)

--[[ The other account, on the other faction. Same auction house here, so the
     prices apply -- and aux files them under a different internal key, which
     is why the file is read into whatever table this character happens to
     use rather than one named after a faction. ]]
UnitFactionGroup = function() return "Alliance" end
aux = { faction_data = { history = {} } }
local got = VendorTruth.PullScan()
check("the other account takes it in", got and got.added, 2)
check("across factions, because the auction house is shared",
    aux.faction_data.history["100:0"], "1789531200#5000#")

----------------------------------------------------------------------
-- merging must only ever lower a price
----------------------------------------------------------------------
--[[ What aux keeps is "the cheapest this was seen for". Between two honest
     looks at the same auction house the lower one is the answer, and a merge
     that could raise a figure would discard something really seen. ]]
aux = { faction_data = { history = {
    ["100:0"] = "1789999999#3000#",            -- ours is cheaper
    ["200:0"] = "1789999999#8000#1@2",         -- theirs is cheaper
} } }
got = VendorTruth.PullScan()
check("a worse price is not taken", aux.faction_data.history["100:0"],
    "1789999999#3000#")
check("a better one is", VendorTruth.DailyMin(aux.faction_data.history["200:0"]), 7000)
check("and only the price changed, not our stored days",
    aux.faction_data.history["200:0"], "1789999999#7000#1@2")
check("the counts say what happened", got and got.lowered, 1)
check("and what was left alone", got and got.skipped, 1)

----------------------------------------------------------------------
-- refusing the wrong file
----------------------------------------------------------------------
--[[ A scan from another realm is a different auction house entirely. Taking it
     would not be an approximation, it would be fiction. ]]
GetRealmName = function() return "SomewhereElse" end
aux = { faction_data = { history = {} } }
local bad, why = VendorTruth.PullScan()
check("a realm with no scan of its own gets nothing", bad, nil)
check("and is told why", string.find(why or "", "no shared scan") ~= nil, true)

FOLDER["VendorTruth_scan_SomewhereElse.txt"] = "VTSHARE1:NZoth;100:0=1#2#"
bad, why = VendorTruth.PullScan()
check("a file belonging to another realm is refused", bad, nil)
check("rather than quietly merged", string.find(why or "", "refusing") ~= nil, true)

----------------------------------------------------------------------
-- failing safely
----------------------------------------------------------------------
GetRealmName = function() return "N'Zoth" end
aux = nil
local n, err = VendorTruth.ShareScan()
check("with no aux there is nothing to share", n, nil)
check("and it says so", string.find(err or "", "aux") ~= nil, true)

aux = { faction_data = { history = { ["1:0"] = "1#2#" } } }
WriteCustomFile, ReadCustomFile = nil, nil
n, err = VendorTruth.ShareScan()
check("without Nampower's file API it declines", n, nil)
check("and says that too", string.find(err or "", "Nampower") ~= nil, true)

print(string.format("\n%d checks, %d failed\n", checks, failures))
if failures > 0 then os.exit(1) end
