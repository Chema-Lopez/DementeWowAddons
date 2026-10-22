-- TransmogAtlas: weekly lockouts (which bosses each character has already killed).
--
-- Source of truth is the game's own raid info:
--   GetSavedInstanceInfo(i)              -> which instance/difficulty the character is saved to and
--                                           when it resets (14th return is the instance map ID)
--   EJ_GetEncounterInfo(journalID)       -> dungeonEncounterID (7th) and map ID (8th) of a boss
--   C_RaidLocks.IsEncounterComplete(...) -> whether that boss is dead on that difficulty (this is
--                                           what the Adventure Guide uses for its "defeated" mark)
-- Results are stored per character in TransmogAtlasDB.chars, so alts are known as well.

local ADDON, ns = ...

local Lockouts = { version = 0 }
ns.Lockouts = Lockouts

local JOB = "lockouts"
local dirty = false
local lastRequest = 0

-- Short difficulty labels for cards and lists (same in every language).
Lockouts.SHORT = {
    [17] = "LFR", [7] = "LFR", [14] = "N", [15] = "H", [16] = "M",
    [1] = "N", [2] = "H", [23] = "M", [3] = "10N", [4] = "25N", [5] = "10H", [6] = "25H", [9] = "40",
}
local MERGED_SHORT = { [3] = "N", [4] = "N", [5] = "H", [6] = "H" } -- both sizes are the same

function Lockouts.CharKey()
    local name = UnitName("player")
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not name or not realm then return nil end
    return name .. "-" .. realm
end

-- Journal encounter -> { d = dungeonEncounterID, m = instance map ID } (static data, cached).
local function EncounterInfo(encounterID)
    local db = ns.db
    local cached = db.encInfo[encounterID]
    if cached then return cached end
    local _, _, _, _, _, _, dungeonEncounterID, mapID = EJ_GetEncounterInfo(encounterID)
    if not dungeonEncounterID then return nil end
    cached = { d = dungeonEncounterID, m = mapID }
    db.encInfo[encounterID] = cached
    return cached
end
Lockouts.EncounterInfo = EncounterInfo

-- Map ID of a journal instance, taken from its first boss (cached in the instance entry).
local function InstanceMapID(instanceID, entry)
    if entry.mapID then return entry.mapID end
    for _, encounterID in ipairs(entry.encOrder or {}) do
        local info = EncounterInfo(encounterID)
        if info and info.m then
            entry.mapID = info.m
            return info.m
        end
    end
    return nil
end

local function IsComplete(mapID, dungeonEncounterID, difficultyID)
    if not (C_RaidLocks and C_RaidLocks.IsEncounterComplete) then return nil end
    local ok, res = pcall(C_RaidLocks.IsEncounterComplete, mapID, dungeonEncounterID, difficultyID)
    if ok and type(res) == "boolean" then return res end
    return nil
end

local function UpdateJob()
    local db = ns.db
    local key = Lockouts.CharKey()
    if not key then return end
    -- EJ_GetEncounterInfo is a plain lookup (it does not touch the Adventure Guide selection); only
    -- load the guide's addon if the function is somehow not there yet.
    if not EJ_GetEncounterInfo then ns.Scanner.EnsureJournal() end

    -- 1) What the character is saved to.
    local now = time()
    local savedByMap, savedByName = {}, {}
    local count = 0
    for i = 1, GetNumSavedInstances() or 0 do
        local name, _, reset, difficultyID, locked, extended, _, _, _, _, numEncounters, encounterProgress, _, mapID = GetSavedInstanceInfo(i)
        if (locked or extended) and reset and reset > 0 and difficultyID then
            local lock = { expires = now + reset, total = numEncounters, progress = encounterProgress, mapID = mapID, difficultyID = difficultyID }
            if mapID then
                savedByMap[mapID] = savedByMap[mapID] or {}
                savedByMap[mapID][difficultyID] = lock
            end
            if name then
                savedByName[name] = savedByName[name] or {}
                savedByName[name][difficultyID] = lock
            end
            count = count + 1
        end
    end

    -- 2) Which bosses are dead, per journal instance and difficulty.
    local saves = {}
    if count > 0 then
        for instanceID, entry in pairs(db.instances) do
            local mapID = InstanceMapID(instanceID, entry)
            local locks = (mapID and savedByMap[mapID]) or savedByName[entry.name or ""]
            if locks then
                for difficultyID, lock in pairs(locks) do
                    local killed, k = {}, 0
                    local checked = false
                    for _, encounterID in ipairs(entry.encOrder or {}) do
                        local info = EncounterInfo(encounterID)
                        local done = info and IsComplete(info.m or lock.mapID or mapID, info.d, difficultyID)
                        if done ~= nil then checked = true end
                        if done then killed[encounterID] = true; k = k + 1 end
                    end
                    if not checked then k = lock.progress or 0 end -- API not available: count only
                    saves[instanceID] = saves[instanceID] or {}
                    saves[instanceID][difficultyID] = {
                        expires = lock.expires,
                        killed = killed,
                        k = k,
                        n = (#(entry.encOrder or {}) > 0) and #entry.encOrder or (lock.total or 0),
                    }
                end
            end
            ns.Checkpoint()
        end
    end

    local _, classFile = UnitClass("player")
    db.chars[key] = {
        name = UnitName("player"),
        class = classFile,
        level = UnitLevel("player"),
        updated = now,
        saves = saves,
    }
    return count
end

local function StartUpdate()
    if not ns.db then return end
    if ns.Runner:IsRunning(JOB) then dirty = true; return end
    ns.Runner:Start(JOB, UpdateJob, {
        onDone = function(count)
            Lockouts.version = Lockouts.version + 1
            ns.Log("DEBUG", "Lockouts updated: %s saved instances", tostring(count))
            ns.Fire("LOCKOUTS_CHANGED")
            if dirty then dirty = false; StartUpdate() end
        end,
        onStop = function() dirty = false end,
    })
end
Lockouts.Update = StartUpdate

-- Asks the server for fresh raid info; UPDATE_INSTANCE_INFO arrives afterwards.
function Lockouts.Request()
    local now = GetTime()
    if now - lastRequest < 3 then return end
    lastRequest = now
    RequestRaidInfo()
end

local function ActiveSaveExact(char, instanceID, difficultyID)
    local saves = char and char.saves and char.saves[instanceID]
    local save = saves and saves[difficultyID]
    if save and save.expires and save.expires > time() then return save end
    return nil
end

-- A save on the other size of an old raid counts too when both sizes drop the same pieces
-- (Cataclysm and Mists of Pandaria raids, which also share the lockout).
local function ActiveSave(char, instanceID, difficultyID)
    local save = ActiveSaveExact(char, instanceID, difficultyID)
    if save then return save end
    local twin = ns.Stats.Twin(instanceID, difficultyID)
    return twin and ActiveSaveExact(char, instanceID, twin) or nil
end

-- Save of the current character for an instance difficulty, or nil.
function Lockouts.Get(instanceID, difficultyID)
    local key = Lockouts.CharKey()
    return key and ActiveSave(ns.db.chars[key], instanceID, difficultyID)
end

function Lockouts.IsKilled(instanceID, difficultyID, encounterID)
    local save = Lockouts.Get(instanceID, difficultyID)
    return save ~= nil and save.killed[encounterID] == true
end

-- "H 5/9  M 2/8" for the current character (only difficulties with a save).
function Lockouts.Summary(instanceID)
    local key = Lockouts.CharKey()
    local char = key and ns.db.chars[key]
    local entry = ns.db.instances[instanceID]
    if not (char and entry) then return nil end
    local parts, done = {}, {}
    for _, difficultyID in ipairs(entry.diffList or {}) do
        local twin = ns.Stats.Twin(instanceID, difficultyID)
        local save = not done[difficultyID] and ActiveSave(char, instanceID, difficultyID)
        if save then
            local label = (twin and MERGED_SHORT[difficultyID]) or Lockouts.SHORT[difficultyID] or tostring(difficultyID)
            parts[#parts + 1] = string.format("%s %d/%d", label, save.k, save.n)
            if twin then done[twin] = true end
        end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, "  ")
end

-- Every known character with its state for an instance difficulty:
-- { {key, name, class, k, n, free, current}, ... } sorted with the current character first.
function Lockouts.Characters(instanceID, difficultyID)
    local list = {}
    local current = Lockouts.CharKey()
    for key, char in pairs(ns.db.chars) do
        local save = ActiveSave(char, instanceID, difficultyID)
        list[#list + 1] = {
            key = key, name = char.name or key, class = char.class,
            k = save and save.k or 0, n = save and save.n or 0,
            free = save == nil, current = key == current,
        }
    end
    table.sort(list, function(a, b)
        if a.current ~= b.current then return a.current end
        if a.free ~= b.free then return a.free end
        return a.name < b.name
    end)
    return list
end

function Lockouts.ColoredName(name, classFile)
    local color = classFile and C_ClassColor and C_ClassColor.GetClassColor(classFile)
    if color then return color:WrapTextInColorCode(name) end
    return name
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("UPDATE_INSTANCE_INFO")
events:RegisterEvent("BOSS_KILL")
events:RegisterEvent("ENCOUNTER_END")
events:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(8, Lockouts.Request)
    elseif event == "UPDATE_INSTANCE_INFO" then
        StartUpdate()
    elseif event == "BOSS_KILL" then
        C_Timer.After(2, Lockouts.Request)
    elseif event == "ENCOUNTER_END" then
        local success = select(5, ...)
        if success == 1 then C_Timer.After(2, Lockouts.Request) end
    end
end)
