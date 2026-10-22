-- TransmogAtlas: reverse index (piece -> where it drops) and search.
-- Built in the background from the scanned data; only kept in memory.

local ADDON, ns = ...

local Index = {
    where = nil,   -- [sourceID] = packed location (first place it drops)
    waiters = {},
}
ns.Index = Index

local BUILD_JOB = "index"
local SEARCH_JOB = "search"
local MAX_ITEM_RESULTS = 150

-- instanceID * 1e9 + difficultyID * 1e6 + encounterID fits exactly in a Lua number.
local function Pack(instanceID, difficultyID, encounterID)
    return instanceID * 1e9 + difficultyID * 1e6 + encounterID
end

local function Unpack(v)
    local instanceID = math.floor(v / 1e9)
    local rest = v - instanceID * 1e9
    local difficultyID = math.floor(rest / 1e6)
    return instanceID, difficultyID, rest - difficultyID * 1e6
end

local function BuildJob()
    local where = {}
    for instanceID, entry in pairs(ns.db.instances) do
        for difficultyID, d in pairs(entry.diffs or {}) do
            for encounterID, list in pairs(d.enc or {}) do
                for _, sourceID in ipairs(list) do
                    if not where[sourceID] then where[sourceID] = Pack(instanceID, difficultyID, encounterID) end
                end
                ns.Checkpoint()
            end
        end
    end
    return where
end

function Index.Invalidate()
    Index.where = nil
    if ns.Runner:IsRunning(BUILD_JOB) then ns.Runner:Stop(BUILD_JOB) end
end

-- Calls fn() once the index is ready (immediately if it already is).
function Index.Ensure(fn)
    if Index.where then
        if fn then fn() end
        return true
    end
    if fn then table.insert(Index.waiters, fn) end
    if not ns.Runner:IsRunning(BUILD_JOB) then
        ns.Runner:Start(BUILD_JOB, BuildJob, {
            pauseInCombat = false,
            onDone = function(where)
                Index.where = where
                local waiters = Index.waiters
                Index.waiters = {}
                for _, w in ipairs(waiters) do ns.SafeCall("index waiter", w) end
                ns.Fire("INDEX_READY")
            end,
            onStop = function() Index.waiters = {} end,
        })
    end
    return false
end

-- instanceID, difficultyID, encounterID of the first place a piece drops (nil if unknown).
function Index.Where(sourceID)
    local v = Index.where and Index.where[sourceID]
    if not v then return nil end
    return Unpack(v)
end

---------------------------------------------------------------------------
-- Search
---------------------------------------------------------------------------

Index.searchQuery = nil
Index.searchResult = nil

local function Matches(text, query)
    return text and text:lower():find(query, 1, true) ~= nil
end

local function SearchJob(query, classID, missingOnly)
    ns.Stats.WarmCollection()
    local db = ns.db
    local result = { instances = {}, encounters = {}, items = {}, truncated = false }

    local instanceOfEncounter = {}
    for instanceID, entry in pairs(db.instances) do
        if Matches(entry.name, query) then result.instances[#result.instances + 1] = instanceID end
        for _, encounterID in ipairs(entry.encOrder or {}) do
            instanceOfEncounter[encounterID] = instanceOfEncounter[encounterID] or instanceID
        end
    end
    ns.Checkpoint()
    for encounterID, name in pairs(db.enc) do
        if instanceOfEncounter[encounterID] and Matches(name, query) then
            result.encounters[#result.encounters + 1] = { encounterID = encounterID, instanceID = instanceOfEncounter[encounterID] }
        end
    end
    ns.Checkpoint()

    -- Items: names come from the client's item cache, which the scan already filled.
    for sourceID, meta in pairs(db.src) do
        local name = meta.i and C_Item.GetItemNameByID(meta.i)
        if name and Matches(name, query) and ns.Stats.Usable(sourceID, classID)
            and not (missingOnly and ns.Stats.IsCollected(sourceID)) then
            if #result.items >= MAX_ITEM_RESULTS then
                result.truncated = true
                break
            end
            result.items[#result.items + 1] = sourceID
        end
        ns.Checkpoint()
    end

    table.sort(result.instances, function(a, b) return (db.instances[a].name or "") < (db.instances[b].name or "") end)
    table.sort(result.encounters, function(a, b) return (db.enc[a.encounterID] or "") < (db.enc[b.encounterID] or "") end)
    return result
end

-- Starts a search; the result arrives through onReady(result). Only the latest query counts.
function Index.Search(text, settings, onReady)
    local query = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if ns.Runner:IsRunning(SEARCH_JOB) then ns.Runner:Stop(SEARCH_JOB) end
    Index.searchQuery = query
    Index.searchResult = nil
    if #query < 2 then return end
    local classID = ns.Stats.ResolveClass(settings.filter)
    local missingOnly = settings.missingOnly
    -- A stopped job is only removed on the next frame: wait for it before starting again.
    local function Start()
        if Index.searchQuery ~= query then return end
        if ns.Runner:IsRunning(SEARCH_JOB) then C_Timer.After(0.05, Start); return end
        ns.Runner:Start(SEARCH_JOB, function() return SearchJob(query, classID, missingOnly) end, {
            pauseInCombat = false,
            onDone = function(result)
                if Index.searchQuery ~= query then return end
                Index.searchResult = result
                if onReady then onReady(result) end
            end,
        })
    end
    Start()
end
