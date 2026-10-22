-- MountAtlas: "What mounts should I farm today?"
-- Missing raid and dungeon mounts with a known drop chance (from Rarity), from expansions up to
-- the chosen one (soloable content), best odds first and bosses already killed (this week or today)
-- last.
--
-- Rarity only knows the lockouts of the character that is logged in, so on every login and kill
-- MountAtlas saves which mounts' bosses (any mount Rarity has lockout data for: raids, dungeons,
-- world bosses, rares) each character has killed and until when (account-wide). That is what the
-- "free on" / "killed on" alt lines use. Raids and world bosses reset weekly; the rest is taken as
-- daily, which is true for the old heroic dungeons and most rares that drop mounts.

local ADDON, ns = ...
local L = ns.L

local Farm = {}
ns.Farm = Farm

local FARM_TYPES = { raid = true, dungeon = true, rare = true } -- rare = rares and world bosses

function Farm.CharKey()
    local name, realm = UnitName("player"), GetNormalizedRealmName()
    if not (name and realm) then return nil end
    return name .. "-" .. realm
end

-- Every farmable mount (collected or not), as { mount, sub, group }.
local function Candidates()
    local list, seen = {}, {}
    local maxExpansion = ns.S().farmMaxExpansion
    for _, group in ipairs(ns.DATA) do
        if group.expansion and group.expansion <= maxExpansion then
            for _, sub in ipairs(group.subs) do
                if FARM_TYPES[sub.type] and (sub.type ~= "rare" or ns.S().farmRares) then
                    for _, m in ipairs(sub.mounts) do
                        if not seen[m.id] and ns.Availability(m, group) ~= "unobtainable"
                            and ns.FactionAllowed(m) and ns.Rarity.Chance(m.id) then
                            seen[m.id] = true
                            list[#list + 1] = { mount = m, sub = sub, group = group }
                        end
                    end
                end
            end
        end
    end
    return list
end

function Farm.IsWeekly(sub, item)
    return sub.type == "raid" or sub.name == "World Boss" or (item and item.worldBossFactionless) and true or false
end

-- Saves this character's kills for every mount with lockout data in Rarity.
function Farm.Snapshot()
    if not ns.Rarity.IsAvailable() then return end
    local key = Farm.CharKey()
    if not key then return end
    local now = time()
    local weekly = now + (C_DateAndTime.GetSecondsUntilWeeklyReset() or 0)
    local daily = now + (C_DateAndTime.GetSecondsUntilDailyReset() or 0)
    local killed, seen = {}, {}
    for _, group in ipairs(ns.DATA) do
        for _, sub in ipairs(group.subs) do
            for _, m in ipairs(sub.mounts) do
                if not seen[m.id] then
                    seen[m.id] = true
                    if ns.Rarity.Defeated(m.id) then
                        killed[m.id] = Farm.IsWeekly(sub, ns.Rarity.Item(m.id)) and weekly or daily
                    end
                end
            end
        end
    end
    local _, class = UnitClass("player")
    ns.db.chars[key] = { class = class, killed = killed, seen = now }
end

local function ClassColored(key, class)
    local name = key:match("^[^-]+") or key
    local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return color and color:WrapTextInColorCode(name) or name
end

-- Returns two lists of coloured alt names: free this lockout and killed this lockout.
-- The current character is left out (its state comes from Rarity directly).
function Farm.Alts(mountID)
    local free, killed = {}, {}
    local me, now = Farm.CharKey(), time()
    for key, char in pairs(ns.db.chars) do
        if key ~= me then
            local expires = char.killed and char.killed[mountID]
            if expires and expires > now then
                killed[#killed + 1] = ClassColored(key, char.class)
            else
                free[#free + 1] = ClassColored(key, char.class)
            end
        end
    end
    table.sort(free); table.sort(killed)
    return free, killed
end

-- Missing farmable mounts, sorted: not killed before killed, then best chance first.
function Farm.List()
    local list = {}
    for _, e in ipairs(Candidates()) do
        if not ns.Mount(e.mount).collected then
            e.chance = ns.Rarity.Chance(e.mount.id)
            e.defeated = ns.Rarity.Defeated(e.mount.id) == true
            list[#list + 1] = e
        end
    end
    table.sort(list, function(a, b)
        if a.defeated ~= b.defeated then return not a.defeated end
        if a.chance ~= b.chance then return a.chance > b.chance end
        return ns.Mount(a.mount).name < ns.Mount(b.mount).name
    end)
    return list
end

-- Expansions offered in the "farm up to" option, oldest first.
function Farm.Expansions()
    local list, seen = {}, {}
    for _, group in ipairs(ns.DATA) do
        if group.expansion and not seen[group.expansion] then
            seen[group.expansion] = true
            list[#list + 1] = group
        end
    end
    table.sort(list, function(a, b) return a.expansion < b.expansion end)
    return list
end

-- Rarity refreshes its lockouts a few seconds after these events.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("UPDATE_INSTANCE_INFO")
events:RegisterEvent("BOSS_KILL")
events:RegisterEvent("ENCOUNTER_END")
events:RegisterEvent("LOOT_CLOSED") -- world bosses: the hidden quest is flagged around the loot
local pending = false
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then RequestRaidInfo() end
    if pending or not ns.db then return end
    pending = true
    C_Timer.After(6, function()
        pending = false
        Farm.Snapshot()
        if ns.UI then ns.UI.Refresh() end
    end)
end)
