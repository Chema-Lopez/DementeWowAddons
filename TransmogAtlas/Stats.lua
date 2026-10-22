-- TransmogAtlas: completion percentages computed from the scanned data.
--
-- It never touches the Adventure Guide: it only asks the collection whether each appearance is
-- known, and caches the answer until the collection changes. Whatever the game reports is what
-- counts, so appearances the game unlocks automatically (for example lower-difficulty versions)
-- are counted as collected as soon as the game says so.

local ADDON, ns = ...

local Stats = {
    results = {}, -- [filter|difficulty] = result
    status = {},  -- [sourceID] = 0 (missing), 1 (appearance known from another item), 2 (this exact item)
    warmed = false,
    version = 0,  -- increases every time cached results are dropped
}
ns.Stats = Stats

local JOB = "stats"

-- Difficulty groups for the difficulty filter (Adventure Guide difficulty IDs).
Stats.DIFFICULTY_GROUPS = {
    { key = "LFR", ids = { 17, 7 } },
    { key = "NORMAL", ids = { 14, 1, 3, 4, 9 } },
    { key = "HEROIC", ids = { 15, 2, 5, 6 } },
    { key = "MYTHIC", ids = { 16, 23 } },
}
local groupOf = {}
for _, group in ipairs(Stats.DIFFICULTY_GROUPS) do
    for _, id in ipairs(group.ids) do groupOf[id] = group.key end
end

function Stats.DifficultyAllowed(difficultyID, filter)
    return filter == nil or filter == "ALL" or groupOf[difficultyID] == filter
end

-- Collection status of a source (cached).
function Stats.Status(sourceID)
    local v = Stats.status[sourceID]
    if v ~= nil then return v end
    v = 0
    local info = C_TransmogCollection.GetAppearanceInfoBySource(sourceID)
    if info then
        -- Permanent/conditional cover sources the game grants automatically (e.g. lower-difficulty
        -- variants of a set unlocked by collecting a higher one).
        if info.sourceIsCollected or info.sourceIsCollectedPermanent or info.sourceIsCollectedConditional then
            v = 2
        elseif info.appearanceIsCollected then
            v = 1
        end
    end
    Stats.status[sourceID] = v
    return v
end

-- A piece counts as collected only when that exact item (source) is known. Knowing the same look
-- from a different item (status 1) is shown separately but still counts as missing.
function Stats.IsCollected(sourceID)
    return Stats.Status(sourceID) == 2
end

-- "ALL", "MINE" or a classID -> classID, or nil for every class.
function Stats.ResolveClass(filter)
    if filter == "MINE" then return ns.Classes.PlayerClassID() end
    if type(filter) == "number" then return filter end
    return nil
end

function Stats.Usable(sourceID, classID)
    if not classID then return true end
    return ns.Classes.CanUseSource(sourceID, classID)
end

-- 10- and 25-player versions of old raids. In Cataclysm and Mists of Pandaria raids both sizes drop
-- exactly the same pieces (and share the weekly lockout); in Wrath of the Lich King they do not.
-- Decided from the scanned data: two sizes are "twins" when their piece lists are identical.
local SIZE_PAIR = { [3] = 4, [4] = 3, [5] = 6, [6] = 5 }
Stats.twins = {} -- [instanceID] = { [difficultyID] = twin difficultyID or false }

local function SourceSet(d)
    local set, n = {}, 0
    for _, list in pairs(d.enc or {}) do
        for _, sourceID in ipairs(list) do
            if not set[sourceID] then set[sourceID] = true; n = n + 1 end
        end
    end
    return set, n
end

function Stats.Twin(instanceID, difficultyID)
    local other = SIZE_PAIR[difficultyID]
    if not other then return nil end
    local cache = Stats.twins[instanceID]
    if not cache then cache = {}; Stats.twins[instanceID] = cache end
    if cache[difficultyID] == nil then
        local result = false
        local entry = ns.db.instances[instanceID]
        local a = entry and entry.diffs and entry.diffs[difficultyID]
        local b = entry and entry.diffs and entry.diffs[other]
        if a and b and a.done and b.done then
            local setA, nA = SourceSet(a)
            local setB, nB = SourceSet(b)
            if nA > 0 and nA == nB then
                result = other
                for sourceID in pairs(setA) do
                    if not setB[sourceID] then result = false; break end
                end
            end
        end
        cache[difficultyID] = result
        cache[other] = result and difficultyID or false
    end
    return cache[difficultyID] or nil
end

function Stats.GroupOf(difficultyID)
    return groupOf[difficultyID]
end

local function Key(settings)
    return tostring(settings.filter) .. "|" .. tostring(settings.difficulty)
end

local function NewCounter() return { t = 0, c = 0 } end

local function Add(counter, collected)
    counter.t = counter.t + 1
    if collected then counter.c = counter.c + 1 end
end

local function Merge(into, from)
    if not from then return end
    into.t = into.t + from.t
    into.c = into.c + from.c
end

-- Makes the client load the appearance collection before querying it; otherwise some queries can
-- report "not collected" just because the data is not loaded yet.
function Stats.WarmCollection()
    if Stats.warmed then return end
    local t0 = debugprofilestop()
    local num = (Enum.TransmogCollectionTypeMeta and Enum.TransmogCollectionTypeMeta.NumValues) or 30
    for category = 1, num - 1 do
        C_TransmogCollection.GetCategoryAppearances(category)
        ns.Checkpoint()
    end
    -- Transmog set data is needed for class-restricted pieces (set class masks).
    C_TransmogSets.GetAllSets()
    ns.Checkpoint()
    Stats.warmed = true
    ns.Log("INFO", "Collection warmed (%d categories, %.0f ms of work)", num - 1, debugprofilestop() - t0)
end

local function ComputeJob(filter, difficulty)
    Stats.WarmCollection()
    local db = ns.db
    local classID = Stats.ResolveClass(filter)
    local result = { total = NewCounter(), tiers = {}, inst = {} }

    for instanceID, entry in pairs(db.instances) do
        local ir = { total = NewCounter(), diffs = {} }
        local seenInstance = {}
        for difficultyID, d in pairs(entry.diffs or {}) do
            if Stats.DifficultyAllowed(difficultyID, difficulty) then
                local dr = { total = NewCounter(), enc = {} }
                local seenDifficulty = {}
                for encounterID, list in pairs(d.enc or {}) do
                    local er = NewCounter()
                    local seenEncounter = {}
                    for _, sourceID in ipairs(list) do
                        if not seenEncounter[sourceID] and Stats.Usable(sourceID, classID) then
                            seenEncounter[sourceID] = true
                            local collected = Stats.IsCollected(sourceID)
                            Add(er, collected)
                            if not seenDifficulty[sourceID] then seenDifficulty[sourceID] = true; Add(dr.total, collected) end
                            if not seenInstance[sourceID] then seenInstance[sourceID] = true; Add(ir.total, collected) end
                        end
                    end
                    dr.enc[encounterID] = er
                    ns.Checkpoint()
                end
                ir.diffs[difficultyID] = dr
            end
        end
        result.inst[instanceID] = ir
        Merge(result.total, ir.total)
    end

    -- Per-expansion totals, using the guide's membership lists (an instance can be in several).
    for tier, membership in pairs(db.tierInstances) do
        local tr = { all = NewCounter(), raids = NewCounter(), dungeons = NewCounter() }
        for _, id in ipairs(membership.raids or {}) do
            local ir = result.inst[id]
            if ir then Merge(tr.raids, ir.total); Merge(tr.all, ir.total) end
        end
        for _, id in ipairs(membership.dungeons or {}) do
            local ir = result.inst[id]
            if ir then Merge(tr.dungeons, ir.total); Merge(tr.all, ir.total) end
        end
        result.tiers[tier] = tr
    end
    return result
end

-- Returns the result if already computed; otherwise starts computing it and returns nil.
function Stats.Get(settings)
    local key = Key(settings)
    local r = Stats.results[key]
    if r then return r end
    if not ns.Runner:IsRunning(JOB) then
        local filter, difficulty = settings.filter, settings.difficulty
        ns.Runner:Start(JOB, function() return ComputeJob(filter, difficulty) end, {
            pauseInCombat = false,
            onDone = function(res)
                Stats.results[key] = res
                if ns.UI and ns.UI.OnStatsReady then ns.UI.OnStatsReady() end
                ns.Fire("STATS_READY")
            end,
        })
    end
    return nil
end

-- Cached result only (never starts a computation).
function Stats.Peek(settings)
    return Stats.results[Key(settings)]
end

function Stats.IsComputing()
    return ns.Runner:IsRunning(JOB)
end

-- Drops cached results (e.g. after a scan or when an appearance is learned).
function Stats.Invalidate(keepStatus)
    wipe(Stats.results)
    if not keepStatus then wipe(Stats.status) end
    if ns.Runner:IsRunning(JOB) then ns.Runner:Stop(JOB) end
    if not keepStatus then wipe(Stats.twins) end
    Stats.version = Stats.version + 1
    ns.Fire("STATS_INVALIDATED")
end

-- Counts collected/total pieces of one instance difficulty right now (synchronous, small).
function Stats.CountDifficulty(instanceID, difficultyID, classID)
    local entry = ns.db.instances[instanceID]
    local d = entry and entry.diffs and entry.diffs[difficultyID]
    local counter = NewCounter()
    if not d then return counter end
    local seen = {}
    for _, list in pairs(d.enc or {}) do
        for _, sourceID in ipairs(list) do
            if not seen[sourceID] and Stats.Usable(sourceID, classID) then
                seen[sourceID] = true
                Add(counter, Stats.IsCollected(sourceID))
            end
        end
    end
    return counter
end

function Stats.Percent(counter)
    if not counter or counter.t == 0 then return nil end
    return counter.c / counter.t * 100
end

-- When the collection changes, refresh once instead of recomputing several times in a row.
local pending = false
local function OnCollectionChanged()
    if pending then return end
    pending = true
    C_Timer.After(2, function()
        pending = false
        Stats.Invalidate()
        if ns.UI and ns.UI.OnStatsReady then ns.UI.OnStatsReady() end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("TRANSMOG_COLLECTION_SOURCE_ADDED")
events:RegisterEvent("TRANSMOG_COLLECTION_SOURCE_REMOVED")
-- TRANSMOG_COLLECTION_UPDATED is deliberately not used: it also fires while querying/warming the
-- collection and could trigger recomputation loops.
events:SetScript("OnEvent", function(_, event)
    ns.Log("DEBUG", "Collection changed (%s)", event)
    OnCollectionChanged()
end)
