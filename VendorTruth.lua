--[[ VendorTruth -- make vendor prices on this server the ones that get used.

     WHY THIS EXISTS

     aux already finds auctions worth buying to vendor: its search filter
     "vendor-profit/<amount>" compares a listing's buyout against what a vendor
     pays. The finding was never the problem. The prices were.

     aux asks its own cache first -- prices it watched a vendor quote, so they
     are true here -- and falls back to ShaguTweaks.SellValueDB, a static table
     of about twenty thousand items compiled for vanilla/Turtle. On this server
     that table is wrong often enough to matter, and wrong in the direction
     that costs money:

       - 1251 items where it claims MORE than a vendor here pays, by up to
         6g25s each;
       - 223 items it prices at up to 18g88s that vendors here REFUSE to buy
         at all.

     The second group is the dangerous one. An item the table values at 18g
     looks like the best flip on the auction house, and the vendor will not
     take it. Nothing warns you; you simply own it.

     WHAT THIS DOES

     The SellValue addon has been recording what vendors actually pay as you
     play, and has thousands of prices from this server sitting unused -- aux
     never looks at it. This copies those over the static ones, so every
     consumer of that table (aux's filter, ShaguTweaks' tooltips, its
     sell-junk) is working from what this server does rather than what vanilla
     did.

     What it cannot do is invent prices for items nobody has sold here yet.
     Those keep the static value, and are flagged on the tooltip as unverified,
     because a quiet guess on an 18g item is the whole problem.
]]

VendorTruth = {}
local VT = VendorTruth

VT.verified = {}   -- [itemID] = true, price seen at a vendor ON THIS SERVER
VT.stats = { corrected = 0, traps = 0, verified = 0, unverified = 0 }
VT.applied = false

local function say(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff7fd5ffVendorTruth|r: " .. msg)
end

--- Copper as "1g23s45c", skipping the parts that are zero.
function VT.Money(c)
    c = math.floor(tonumber(c) or 0)
    local g, s = math.floor(c / 10000), math.floor(math.mod(c, 10000) / 100)
    local out = ""
    if g > 0 then out = out .. g .. "g" end
    if g > 0 or s > 0 then out = out .. s .. "s" end
    return out .. math.mod(c, 100) .. "c"
end

--- The numeric id out of SellValue's "item:1234" keys.
function VT.IdFromKey(key)
    if type(key) ~= "string" then return nil end
    local _, _, id = string.find(key, "^item:(%d+)$")
    return tonumber(id)
end

--[[ Replace the static prices with the ones seen here.

     A zero is copied across as deliberately as a price is. SellValue writes
     zero to mean "the vendor would not buy this", which is a fact about this
     server and the one the static table most needs correcting on -- those are
     the 223 that look like treasure and cannot be sold. ]]
function VT.Apply()
    if type(SellValues) ~= "table" then
        VT.reason = "the SellValue addon is not loaded, so there is nothing " ..
            "recorded from this server to use"
        return false
    end
    local db = ShaguTweaks and ShaguTweaks.SellValueDB
    if type(db) ~= "table" then
        VT.reason = "ShaguTweaks is not providing SellValueDB, which is the " ..
            "table aux reads when its own cache has no price"
        return false
    end

    VT.stats = { corrected = 0, traps = 0, verified = 0, unverified = 0 }

    for key, price in pairs(SellValues) do
        local id = VT.IdFromKey(key)
        if id and type(price) == "number" then
            --[[ SellValue divides a stack's total by its size, so this can be
                 fractional. Rounded DOWN: understating a vendor price costs a
                 missed flip, overstating it costs gold. ]]
            local here = math.floor(price)
            VT.verified[id] = true
            VT.stats.verified = VT.stats.verified + 1
            local was = db[id]
            if was ~= here then
                if was and was > 0 and here == 0 then
                    VT.stats.traps = VT.stats.traps + 1
                end
                db[id] = here
                VT.stats.corrected = VT.stats.corrected + 1
            end
        end
    end

    --[[ Counted only where there is a price to be wrong about. An unverified
         zero misleads nobody -- it claims no profit -- so including it would
         inflate the number and, worse, make it disagree with the count of
         items that can actually show the tooltip warning. The figure reported
         and the figure flagged are deliberately the same figure. ]]
    for id, price in pairs(db) do
        if not VT.verified[id] and price and price > 0 then
            VT.stats.unverified = VT.stats.unverified + 1
        end
    end

    VT.applied = true
    return true
end

--- What we know about one item, and how well we know it.
function VT.Check(id)
    id = tonumber(id)
    if not id then return nil end
    local db = ShaguTweaks and ShaguTweaks.SellValueDB
    local price = db and db[id]
    return {
        id = id,
        price = price,
        verified = VT.verified[id] and true or false,
        sellable = (price or 0) > 0,
    }
end

-- ---------------------------------------------------------------------------
-- Tooltip
-- ---------------------------------------------------------------------------
--[[ The warning goes where the decision is made.

     A price nobody has checked on this server is not a reason to panic -- most
     of them are right -- but it IS a reason not to spend twenty gold on the
     strength of it. The line only appears for the unverified, so it stays
     quiet about the thousands that are known good rather than becoming noise
     that gets ignored. ]]
function VT.DecorateTooltip(tip, link)
    if not link or not VT.applied then return end
    local _, _, id = string.find(link, "item:(%d+)")
    id = tonumber(id)
    if not id then return end
    local info = VT.Check(id)
    if not info or not info.price or info.price <= 0 then return end
    if info.verified then return end
    tip:AddLine("|cffffcc00vendor price unverified on this server|r", 1, 0.8, 0)
    tip:Show()
end

local function hookTooltip()
    --[[ 1.12 has no OnTooltipSetItem, so the Set* calls that put an item in a
         tooltip are wrapped individually. SetHyperlink and SetAuctionItem are
         the two that matter: between them they cover browsing the auction
         house in the default UI and in aux. ]]
    local methods = { "SetHyperlink", "SetAuctionItem" }
    for i = 1, table.getn(methods) do
        local name = methods[i]
        local original = GameTooltip[name]
        if type(original) == "function" and not VT["hooked_" .. name] then
            VT["hooked_" .. name] = true
            GameTooltip[name] = function(self, a, b, c, d)
                local result = original(self, a, b, c, d)
                local link
                if name == "SetHyperlink" then
                    link = a
                elseif GetAuctionItemLink then
                    link = GetAuctionItemLink(a, b)
                end
                VT.DecorateTooltip(self, link)
                return result
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Watchlist
-- ---------------------------------------------------------------------------
--[[ Which items are worth searching for at all.

     Scanning the whole auction house for vendor profit costs several minutes,
     and on this server the entire opportunity is a few silver an item. That
     maths does not work: you cannot spend ten minutes to make thirteen silver.

     aux has already done the looking, though. Every scan it has ever run left
     the lowest buyout it saw in its history table, so the items that get
     listed below vendor price are already on record. Comparing that record
     against the corrected vendor prices gives a short list of names to search
     for directly -- which is seconds, not minutes, because a name search is a
     Blizzard query and only pulls the pages that match.

     aux stores each record as "next_push#daily_min_buyout#value@time;..."
     under a "<itemID>:<suffix>" key. The second field is the cheapest it saw
     today, the rest are previous days. ]]

--- The lowest unit buyout aux has ever recorded for an item, across suffixes.
function VT.LowestSeen()
    local history = aux and aux.faction_data and aux.faction_data.history
    if type(history) ~= "table" then return nil end

    local lowest = {}
    for key, record in pairs(history) do
        local _, _, id = string.find(key, "^(%d+):")
        id = tonumber(id)
        if id and type(record) == "string" then
            --[[ Every price in the record, today's and the stored days both.
                 The cheapest it has EVER been is the question -- a thing that
                 went cheap once will go cheap again. ]]
            local field = 0
            for part in string.gfind(record, "[^#]+") do
                field = field + 1
                if field == 2 then
                    local n = tonumber(part)
                    if n and n > 0 and (not lowest[id] or n < lowest[id]) then
                        lowest[id] = n
                    end
                elseif field >= 3 then
                    for point in string.gfind(part, "[^;]+") do
                        local _, _, v = string.find(point, "^(%d+)@")
                        v = tonumber(v)
                        if v and v > 0 and (not lowest[id] or v < lowest[id]) then
                            lowest[id] = v
                        end
                    end
                end
            end
        end
    end
    return lowest
end

--[[ Items aux has seen listed below what a vendor pays.

     Verified prices only unless `include_guesses`. The margins here are a few
     silver, so one wrong price on an unverified item wipes out a day of them
     -- the asymmetry that justifies ignoring a guess is much sharper when the
     upside is this thin. ]]
function VT.Watchlist(include_guesses)
    local lowest = VT.LowestSeen()
    if not lowest then return nil end
    local db = ShaguTweaks and ShaguTweaks.SellValueDB
    if type(db) ~= "table" then return nil end

    local out = {}
    for id, low in pairs(lowest) do
        local vendor = db[id]
        if vendor and vendor > low and (VT.verified[id] or include_guesses) then
            table.insert(out, {
                id = id, low = low, vendor = vendor,
                margin = vendor - low,
                verified = VT.verified[id] and true or false,
            })
        end
    end
    table.sort(out, function(a, b) return a.margin > b.margin end)
    return out
end

-- ---------------------------------------------------------------------------
-- Sharing a scan between accounts on this machine
-- ---------------------------------------------------------------------------
--[[ SavedVariables live under WTF/Account/<ACCOUNT>/, so one account can never
     read another's -- the account name is in the path. Nampower's
     WriteCustomFile/ReadCustomFile write to CustomData/, which belongs to the
     INSTALLATION rather than the account, and is the only thing here that
     crosses that line.

     A scan is minutes of work and the result is the same for everyone looking
     at the same auction house, so doing it once per account is pure waste.
     Scan on the bank alt, and the main on the other account has the prices
     without ever opening the auction house.

     SCOPED BY REALM, NOT BY FACTION. In vanilla the two factions have separate
     auction houses and merging across them would mean prices from a market you
     cannot visit -- but this server runs a shared one, so a Horde scan is just
     as true for an Alliance character. aux still files its history per faction
     internally; the data is interchangeable here even though its storage is
     not, which is exactly why this reads one file into whichever table the
     current character happens to use. ]]

VT.SHARE_MAGIC = "VTSHARE1"

function VT.FileAPI()
    return WriteCustomFile ~= nil and ReadCustomFile ~= nil
end

--- The market these prices belong to. One auction house per realm here.
function VT.MarketTag()
    local realm = GetRealmName and GetRealmName() or ""
    if realm == "" then return nil end
    return (string.gsub(realm, "[^%w]", ""))
end

function VT.ShareFile(tag)
    return "VendorTruth_scan_" .. (tag or VT.MarketTag() or "unknown") .. ".txt"
end

--- aux's history table for this character, or nil.
function VT.AuxHistory()
    local data = aux and aux.faction_data
    if type(data) ~= "table" or type(data.history) ~= "table" then return nil end
    return data.history
end

--[[ Write this account's scan out.

     aux's own record strings are copied verbatim rather than re-encoded.
     Anything reconstructed here would be a second implementation of aux's
     format, free to drift from the one that has to read it back. ]]
function VT.ShareScan()
    if not VT.FileAPI() then
        return nil, "Nampower's file API is missing, so nothing can be written"
    end
    local history = VT.AuxHistory()
    if not history then
        return nil, "aux has no scan history for this character"
    end
    local tag = VT.MarketTag()
    if not tag then return nil, "cannot tell which realm this is" end

    local parts, n = { VT.SHARE_MAGIC .. ":" .. tag }, 0
    for key, record in pairs(history) do
        if type(record) == "string" then
            table.insert(parts, key .. "=" .. record)
            n = n + 1
        end
    end
    if n == 0 then return nil, "the scan history is empty" end

    local ok = pcall(WriteCustomFile, VT.ShareFile(tag),
                     table.concat(parts, ";"), "w")
    if not ok then return nil, "the write failed" end
    VT.lastShared = n
    return n
end

--- The daily_min_buyout out of one of aux's records (its second field).
function VT.DailyMin(record)
    if type(record) ~= "string" then return nil end
    local field, found = 0, nil
    for part in string.gfind(record, "[^#]+") do
        field = field + 1
        if field == 2 then found = tonumber(part) end
    end
    if found and found > 0 then return found end
    return nil
end

--[[ The same record with a lower minimum, every other field left as aux wrote
     it. next_push is this client's own schedule and the data points are its
     own record of previous days; neither is ours to rewrite. ]]
function VT.WithDailyMin(record, value)
    local out, field, seen = "", 0, 0
    for part, sep in string.gfind(record .. "#", "([^#]*)(#)") do
        field = field + 1
        if field == 2 then part = tostring(value) end
        out = (field == 1) and part or (out .. "#" .. part)
        seen = seen + 1
    end
    return out
end

--[[ Take another account's scan in.

     Only ever LOWERS a price. What aux keeps is "the cheapest this was seen
     for", so between two honest observations of the same auction house the
     lower one is the answer, and a merge that could raise a figure would be
     throwing away something that was really seen. ]]
function VT.PullScan()
    if not VT.FileAPI() then
        return nil, "Nampower's file API is missing, so nothing can be read"
    end
    local history = VT.AuxHistory()
    if not history then
        return nil, "aux has no history table for this character yet - " ..
            "open the auction house once so it makes one"
    end
    local tag = VT.MarketTag()
    if not tag then return nil, "cannot tell which realm this is" end

    local ok, text = pcall(ReadCustomFile, VT.ShareFile(tag))
    if not ok or type(text) ~= "string" or text == "" then
        return nil, "no shared scan found for " .. tag ..
            " - scan on the other account first"
    end

    local prefix = VT.SHARE_MAGIC .. ":" .. tag
    if string.sub(text, 1, string.len(prefix)) ~= prefix then
        -- Refused rather than guessed at: it is a file for somewhere else.
        return nil, "that file is not a scan for " .. tag .. " - refusing it"
    end

    local added, lowered, skipped, first = 0, 0, 0, true
    for chunk in string.gfind(text, "[^;]+") do
        if first then
            first = false
        else
            local _, _, key, record = string.find(chunk, "^([^=]+)=(.*)$")
            if key and record then
                local mine = history[key]
                if not mine then
                    history[key] = record
                    added = added + 1
                else
                    local theirs = VT.DailyMin(record)
                    local ours = VT.DailyMin(mine)
                    if theirs and (not ours or theirs < ours) then
                        history[key] = VT.WithDailyMin(mine, theirs)
                        lowered = lowered + 1
                    else
                        skipped = skipped + 1
                    end
                end
            end
        end
    end
    VT.lastPull = { added = added, lowered = lowered, skipped = skipped }
    return VT.lastPull
end

-- ---------------------------------------------------------------------------
-- Commands
-- ---------------------------------------------------------------------------
function VT.Report()
    if not VT.applied then
        say("|cffff5179not running|r - " .. (VT.reason or "unknown reason"))
        return
    end
    local s = VT.stats
    say(s.verified .. " vendor price(s) recorded on this server are now the " ..
        "ones aux and ShaguTweaks use.")
    say("  " .. s.corrected .. " differed from the static table and were corrected.")
    if s.traps > 0 then
        say("  |cff00ff7f" .. s.traps .. " of those were priced items that " ..
            "vendors here will not buy at all|r - the ones that cost you gold.")
    end
    say("  |cff888888" .. s.unverified .. " item(s) still have only the static " ..
        "price. Those are flagged on the tooltip.|r")
    say("|cffffffff/vt watch|r lists what aux has actually seen below vendor " ..
        "price - far quicker than scanning for it.")
end

function VT.PrintWatchlist(include_guesses)
    local list = VT.Watchlist(include_guesses)
    if not list then
        say("|cffff5179cannot read aux's scan history|r - is aux loaded, and " ..
            "have you run a scan on this character?")
        return
    end
    if table.getn(list) == 0 then
        say("nothing in aux's history has ever been listed below vendor price. " ..
            "|cff888888Run a full scan at the auction house and try again - this " ..
            "can only see what aux has already looked at.|r")
        return
    end

    say(table.getn(list) .. " item(s) aux has seen listed below vendor price:")
    local shown = 0
    for i = 1, table.getn(list) do
        local row = list[i]
        if shown < 20 then
            shown = shown + 1
            local name = GetItemInfo and GetItemInfo(row.id)
            say(string.format("  %s  seen %s, vendor pays %s, |cff00ff7f+%s|r%s",
                name or ("item " .. row.id),
                VT.Money(row.low), VT.Money(row.vendor), VT.Money(row.margin),
                row.verified and "" or " |cffffcc00(unverified)|r"))
        end
    end
    if table.getn(list) > shown then
        say("  |cff888888... and " .. (table.getn(list) - shown) .. " more.|r")
    end
    --[[ The point of the list. A name search is a Blizzard query, so it pulls
         only the matching pages instead of all of them -- seconds rather than
         the minutes a bare vendor-profit scan costs. ]]
    say("|cff888888Search for these by name in aux rather than scanning " ..
        "everything; a name search only pulls the pages that match.|r")
end

SLASH_VENDORTRUTH1 = "/vt"
SLASH_VENDORTRUTH2 = "/vendortruth"
SlashCmdList["VENDORTRUTH"] = function(msg)
    msg = msg or ""
    local _, _, id = string.find(msg, "item:(%d+)")
    if not id then
        local _, _, bare = string.find(msg, "^%s*(%d+)%s*$")
        id = bare
    end

    if string.find(msg, "^%s*share") then
        local n, err = VT.ShareScan()
        if not n then say("|cffff5179could not share|r - " .. err)
        else say("wrote " .. n .. " scanned item(s) for |cffffffff" ..
            tostring(VT.MarketTag()) .. "|r.") end
        return
    end

    if string.find(msg, "^%s*pull") then
        local r, err = VT.PullScan()
        if not r then say("|cffff5179could not pull|r - " .. err)
        else say("took in |cffffffff" .. r.added .. "|r new item(s), lowered " ..
            r.lowered .. ", " .. r.skipped .. " already as good.") end
        return
    end

    if string.find(msg, "^%s*watch") then
        VT.PrintWatchlist(string.find(msg, "all") ~= nil)
        return
    end

    if not id then
        if string.find(msg, "%S") then
            say("|cffffffff/vt|r what was corrected, |cffffffff/vt watch|r " ..
                "what to look for, |cffffffff/vt <item>|r one item. " ..
                "Scans share themselves; |cffffffff/vt share|r and " ..
                "|cffffffff/vt pull|r force it.")
        else
            VT.Report()
        end
        return
    end

    local info = VT.Check(id)
    if not info or not info.price then
        say("item " .. id .. ": |cffffcc00no vendor price known at all|r.")
        return
    end
    if not info.sellable then
        say("item " .. id .. ": |cffff5179vendors will not buy this|r" ..
            (info.verified and " (confirmed here)" or " (per the static table)") ..
            " - do not buy it to vendor.")
        return
    end
    say("item " .. id .. ": vendor pays |cffffffff" .. VT.Money(info.price) .. "|r " ..
        (info.verified
            and "|cff00ff7f(seen at a vendor on this server)|r"
            or "|cffffcc00(static table, never checked here - treat with care)|r"))
end

-- ---------------------------------------------------------------------------
-- Load
-- ---------------------------------------------------------------------------
--[[ On PLAYER_LOGIN, not ADDON_LOADED: SellValue's saved prices and
     ShaguTweaks' table both have to exist first, and login is the first moment
     every addon has had its turn. aux reads the table when a search runs, long
     after, so there is no race to lose. ]]
--[[ Sharing happens by itself, because a step you have to remember is a step
     that does not happen. Closing the auction house is the moment a scan has
     just finished and the client is idle; logout is the backstop for anything
     scanned since. Coming in, the pull is at login, before you would have a
     reason to look. ]]
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("AUCTION_HOUSE_CLOSED")
ev:RegisterEvent("PLAYER_LOGOUT")
ev:SetScript("OnEvent", function()
    if event == "AUCTION_HOUSE_CLOSED" or event == "PLAYER_LOGOUT" then
        local n = VT.ShareScan()
        if n and event == "AUCTION_HOUSE_CLOSED" then
            say("|cff888888shared " .. n .. " item(s) with your other accounts.|r")
        end
        return
    end

    if VT.Apply() then
        hookTooltip()
        --[[ After Apply, so the prices the pulled scan is judged against are
             already the corrected ones. ]]
        local pulled = VT.PullScan()
        if pulled and (pulled.added + pulled.lowered) > 0 then
            say("picked up |cffffffff" .. pulled.added .. "|r item(s) scanned " ..
                "on another account" ..
                (pulled.lowered > 0 and (", and " .. pulled.lowered ..
                    " better price(s)") or "") .. ".")
        end
        if VT.stats.traps > 0 then
            say(VT.stats.traps .. " item(s) the price table called valuable " ..
                "cannot actually be sold here. Corrected. |cffffffff/vt|r for the rest.")
        end
    else
        say("|cffff5179not running|r - " .. (VT.reason or "unknown reason"))
    end
end)
