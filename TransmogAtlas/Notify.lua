-- TransmogAtlas: chat message when a scanned piece is learned, with the new percentage of the
-- instance difficulty it drops in. Several pieces learned at once are grouped per instance.

local ADDON, ns = ...
local L = ns.L

local Notify = {}
ns.Notify = Notify

local FLUSH_DELAY = 2.5 -- after the stats refresh that follows a collection change (2 s)
local queue = {}
local scheduled = false

local function DifficultyName(difficultyID)
    return GetDifficultyInfo(difficultyID) or tostring(difficultyID)
end

local function Percent(counter)
    if counter.t == 0 then return "–" end
    return string.format("%d%% (%d/%d)", math.floor(counter.c / counter.t * 100), counter.c, counter.t)
end

local function Flush()
    local sources = queue
    queue = {}
    if #sources == 0 then return end
    -- The status cache may still hold the old answer for these pieces.
    for _, sourceID in ipairs(sources) do ns.Stats.status[sourceID] = nil end

    local classID = ns.Stats.ResolveClass(ns.db.settings.filter)
    local groups, order = {}, {}
    for _, sourceID in ipairs(sources) do
        local instanceID, difficultyID = ns.Index.Where(sourceID)
        if instanceID then
            local key = instanceID .. ":" .. difficultyID
            if not groups[key] then
                groups[key] = { instanceID = instanceID, difficultyID = difficultyID, sources = {} }
                order[#order + 1] = key
            end
            table.insert(groups[key].sources, sourceID)
        end
    end

    for _, key in ipairs(order) do
        local g = groups[key]
        local entry = ns.db.instances[g.instanceID]
        local where = string.format("%s (%s)", entry and entry.name or "?", DifficultyName(g.difficultyID))
        local counter = ns.Stats.CountDifficulty(g.instanceID, g.difficultyID, classID)
        if #g.sources == 1 then
            local info = C_TransmogCollection.GetAppearanceSourceInfo(g.sources[1])
            local link = info and info.itemLink or "?"
            ns.Print(L["|cff40ff40New piece|r %s — %s: %s"], link, where, Percent(counter))
        else
            ns.Print(L["|cff40ff40%d new pieces|r — %s: %s"], #g.sources, where, Percent(counter))
        end
    end
end

local function Schedule()
    if scheduled then return end
    scheduled = true
    C_Timer.After(FLUSH_DELAY, function()
        scheduled = false
        -- The reverse index is built on first use; flush once it is ready.
        ns.Index.Ensure(function() ns.SafeCall("notify flush", Flush) end)
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("TRANSMOG_COLLECTION_SOURCE_ADDED")
events:SetScript("OnEvent", function(_, _, sourceID)
    local db = ns.db
    if not (db and db.settings.notify and sourceID and db.src[sourceID]) then return end
    queue[#queue + 1] = sourceID
    Schedule()
end)
