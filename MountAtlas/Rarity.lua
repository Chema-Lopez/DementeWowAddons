-- MountAtlas: optional integration with the Rarity addon.
-- Rarity (GPLv2) keeps a hand-researched list of drop chances, attempt counts, boss lockouts and
-- coordinates for rare mounts. Nothing from it is copied into MountAtlas: when Rarity is loaded,
-- its in-memory data is read at runtime. Without Rarity every function here returns nil.
--
-- Fields read from a Rarity item: spellId, itemId, chance (drop chance is 1/chance), attempts,
-- coords ({ m = uiMapID, x, y [0-100] }), sourceText, instanceDifficulties ({ [difficultyID] = true }),
-- lockBossName (English boss name, translated with LibBabble-Boss), lockoutDetails
-- ({ mode = 1 (any) | 2 (all), { encounterName, instanceDifficulties }, ... }) and questId (one or
-- a list of hidden quests flagged when the loot lockout is used: world bosses, many rares).

local ADDON, ns = ...

local RarityAPI = {}
ns.Rarity = RarityAPI

local MODE_ALL = 2 -- Rarity's DEFEAT_DETECTION.MODE_AND

local index -- mountID -> Rarity item (built on first use)

local function RarityAddon()
    local R = _G.Rarity
    if type(R) == "table" and type(R.db) == "table" and R.db.profile and R.db.profile.groups then
        return R
    end
end

function RarityAPI.IsAvailable()
    return RarityAddon() ~= nil
end

local function BuildIndex()
    index = {}
    local R = RarityAddon()
    local mounts = R and R.db.profile.groups.mounts
    if type(mounts) ~= "table" then return end
    for _, item in pairs(mounts) do
        if type(item) == "table" and type(item.chance) == "number" and item.chance > 0 then
            local mountID = (item.spellId and C_MountJournal.GetMountFromSpell(item.spellId))
                or (item.itemId and C_MountJournal.GetMountFromItem(item.itemId))
            if mountID then index[mountID] = item end
        end
    end
end

-- Rarity item for a mountID, or nil.
function RarityAPI.Item(mountID)
    if not RarityAddon() then return nil end
    if not index then BuildIndex() end
    return index[mountID]
end

-- Drop chance as a fraction (0.01 for 1/100), or nil.
function RarityAPI.Chance(mountID)
    local item = RarityAPI.Item(mountID)
    return item and (1 / item.chance)
end

function RarityAPI.Attempts(mountID)
    local item = RarityAPI.Item(mountID)
    return item and (tonumber(item.attempts) or 0)
end

-- Difficulty names the mount drops on ("25 Player (Heroic)"...), or nil.
function RarityAPI.Difficulties(mountID)
    local item = RarityAPI.Item(mountID)
    if not (item and type(item.instanceDifficulties) == "table") then return nil end
    local names = {}
    for difficultyID, on in pairs(item.instanceDifficulties) do
        if on then names[#names + 1] = GetDifficultyInfo(difficultyID) or tostring(difficultyID) end
    end
    if #names == 0 then return nil end
    table.sort(names)
    return table.concat(names, ", ")
end

-- true/false when Rarity knows whether this character already killed the boss this lockout,
-- nil when the item has no lockout information.
function RarityAPI.Defeated(mountID)
    local item = RarityAPI.Item(mountID)
    local R = RarityAddon()
    if not (item and R) then return nil end

    -- Holiday bosses (Headless Horseman, Ahune, Coren Direbrew…): one reward a day per character
    -- through the holiday dungeon finder (lockDungeonId). Rarity fills lockouts_holiday with
    -- GetLFGDungeonRewards: true = done today, false = available, nil = event not active.
    if item.holidayEvents and not RarityAPI.EventActive(mountID) then return nil end
    if item.lockDungeonId then
        local done = (R.lockouts_holiday or {})[item.lockDungeonId]
        if done == nil and GetLFGDungeonRewards then done = GetLFGDungeonRewards(item.lockDungeonId) and true or false end
        return done == true
    end

    -- World bosses, many rares and some holiday items: a hidden quest is flagged when the loot
    -- lockout is used (Rarity checks this first too).
    if item.questId then
        local ids = type(item.questId) == "table" and item.questId or { item.questId }
        for _, questID in pairs(ids) do
            if C_QuestLog.IsQuestFlaggedCompleted(questID) then return true end
        end
        return false
    end

    local details = item.lockoutDetails
    if type(details) == "table" and #details > 0 then
        local requireAll = details.mode == MODE_ALL
        local stored = R.lockouts_detailed or {}
        local anyDone = false
        for _, group in ipairs(details) do
            local done = false
            local kills = type(group.encounterName) == "string" and stored[group.encounterName]
            if kills and type(group.instanceDifficulties) == "table" then
                for difficultyID in pairs(group.instanceDifficulties) do
                    if kills[difficultyID] then done = true end
                end
            end
            if requireAll and not done then return false end
            anyDone = anyDone or done
        end
        return anyDone
    end

    if item.lockBossName then
        local lockouts = R.lockouts or {}
        local babble = LibStub and LibStub("LibBabble-Boss-3.0", true)
        local localized = babble and babble:GetUnstrictLookupTable()[item.lockBossName]
        return (localized and lockouts[localized] == true) or lockouts[item.lockBossName] == true
    end
    return nil
end

-- First usable map position { m, x, y } (x and y from 0 to 1), or nil.
function RarityAPI.Location(mountID)
    local item = RarityAPI.Item(mountID)
    if not (item and type(item.coords) == "table") then return nil end
    for _, c in ipairs(item.coords) do
        if type(c) == "table" and c.m and c.x and c.y then
            return { m = c.m, x = c.x / 100, y = c.y / 100 }
        end
    end
    return nil
end

-- Holiday event mounts (Hallow's End, Brewfest, Love is in the Air…).
function RarityAPI.IsEvent(mountID)
    local item = RarityAPI.Item(mountID)
    return item ~= nil and item.holidayEvents ~= nil
end

local function IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

-- Holiday dungeons are only listed in the dungeon finder while their event is on.
local function HolidayDungeonOffered(dungeonID)
    if not (GetNumRandomDungeons and GetLFGRandomDungeonInfo) then return nil end
    for i = 1, GetNumRandomDungeons() or 0 do
        local id = GetLFGRandomDungeonInfo(i)
        if id == dungeonID then return true end
    end
    return false
end

-- Today's calendar holidays. Since 12.0 some calendar fields can be secret values (Rarity skips the
-- whole event then, which leaves its list empty), so only the event ID is used and checked.
local function CalendarHolidayActive(eventIDs)
    if not (C_Calendar and C_DateAndTime) then return nil end
    local today = C_DateAndTime.GetCurrentCalendarTime()
    local monthInfo = C_Calendar.GetMonthInfo()
    if not (today and monthInfo) then return nil end
    local offset = -12 * (monthInfo.year - today.year) + today.month - monthInfo.month
    local wanted = {}
    for _, id in pairs(eventIDs) do wanted[id] = true end
    for i = 1, C_Calendar.GetNumDayEvents(offset, today.monthDay) or 0 do
        local event = C_Calendar.GetDayEvent(offset, today.monthDay, i)
        local id = event and event.eventID
        if id and not IsSecret(id) and wanted[id] then return true end
    end
    return false
end

-- true when the mount's holiday event is on now (always true for non-event mounts).
function RarityAPI.EventActive(mountID)
    local item = RarityAPI.Item(mountID)
    if not (item and item.holidayEvents) then return true end
    if item.lockDungeonId then
        local offered = HolidayDungeonOffered(item.lockDungeonId)
        if offered ~= nil then return offered end
    end
    if type(item.holidayEvents) == "table" then
        local active = CalendarHolidayActive(item.holidayEvents)
        if active then return true end
    end
    local R = RarityAddon()
    local events = R and R.HolidayEvents
    if events and events.IsItemAvailableToday then return events.IsItemAvailableToday(item) and true or false end
    return false
end

-- Zone (uiMapID) where the mount drops when Rarity has no exact coordinates, for example roaming
-- rares like the Fallen Charger in the Maw. nil when there is an exact location or nothing.
function RarityAPI.Zone(mountID)
    if RarityAPI.Location(mountID) then return nil end
    local item = RarityAPI.Item(mountID)
    if not (item and type(item.coords) == "table") then return nil end
    for _, c in ipairs(item.coords) do
        if type(c) == "table" and c.m then return c.m end
    end
    return nil
end

-- Every mount Rarity knows, as mountID -> Rarity item (empty without Rarity).
function RarityAPI.All()
    if not RarityAddon() then return {} end
    if not index then BuildIndex() end
    return index
end

-- Adventure Guide instance the mount drops in, from Rarity's coordinates (false = none known).
local journalInstance = {}

function RarityAPI.JournalInstance(mountID)
    local cached = journalInstance[mountID]
    if cached ~= nil then return cached or nil end
    local found = false
    local item = RarityAPI.Item(mountID)
    if item and type(item.coords) == "table" then
        for _, c in ipairs(item.coords) do
            local id = type(c) == "table" and c.m and C_EncounterJournal.GetInstanceForGameMap(c.m)
            if id then found = id break end
        end
    end
    journalInstance[mountID] = found
    return found or nil
end

-- Rarity's index is rebuilt after a reload of its data (new attempts do not need it: the item
-- tables are the same objects).
function RarityAPI.Reset() index = nil end
