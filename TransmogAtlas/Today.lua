-- TransmogAtlas: "What should I run?" — instance difficulties ranked by how many missing pieces the
-- current character can still get this week (bosses already killed this week do not count).
-- World boss groups are left out.

local ADDON, ns = ...

local Today = { results = {} }
ns.Today = Today

local JOB = "today"
local MAX_ROWS = 60

local function Key(settings)
    return table.concat({
        tostring(settings.filter), tostring(settings.difficulty),
        tostring(settings.todayRaids), tostring(settings.todayDungeons),
        ns.Stats.version, ns.Lockouts.version, tostring(ns.Lockouts.CharKey()),
    }, "|")
end

local function ComputeJob(settings)
    ns.Stats.WarmCollection()
    local db = ns.db
    local Stats, Lockouts = ns.Stats, ns.Lockouts
    local classID = Stats.ResolveClass(settings.filter)
    local rows = {}

    for instanceID, entry in pairs(db.instances) do
        local wanted = (entry.isRaid and settings.todayRaids) or (not entry.isRaid and settings.todayDungeons)
        -- World bosses are outdoor and spread over a continent: not something to "run".
        if wanted and not ns.Scanner.IsWorldBosses(instanceID) then
            for difficultyID, d in pairs(entry.diffs or {}) do
                -- Old raids whose 10- and 25-player versions drop the same pieces: one row (the 10).
                local twin = Stats.Twin(instanceID, difficultyID)
                if d.done and Stats.DifficultyAllowed(difficultyID, settings.difficulty)
                    and not (twin and twin < difficultyID) then
                    local save = Lockouts.Get(instanceID, difficultyID)
                    local available, seen = 0, {}
                    local freeBosses, bosses = 0, 0
                    for encounterID, list in pairs(d.enc or {}) do
                        local killed = save and encounterID ~= 0 and save.killed[encounterID]
                        local bossMissing = 0
                        for _, sourceID in ipairs(list) do
                            if not seen[sourceID] and Stats.Usable(sourceID, classID) and not Stats.IsCollected(sourceID) then
                                if not killed then
                                    seen[sourceID] = true
                                    available = available + 1
                                end
                                bossMissing = bossMissing + 1
                            end
                        end
                        if encounterID ~= 0 and bossMissing > 0 then
                            bosses = bosses + 1
                            if not killed then freeBosses = freeBosses + 1 end
                        end
                        ns.Checkpoint()
                    end
                    if available > 0 then
                        rows[#rows + 1] = {
                            instanceID = instanceID, difficultyID = difficultyID, available = available,
                            freeBosses = freeBosses, bosses = bosses, saved = save ~= nil, merged = twin ~= nil,
                        }
                    end
                end
            end
        end
    end

    table.sort(rows, function(a, b)
        if a.available ~= b.available then return a.available > b.available end
        local na, nb = db.instances[a.instanceID].name or "", db.instances[b.instanceID].name or ""
        if na ~= nb then return na < nb end
        return a.difficultyID < b.difficultyID
    end)
    local total = #rows
    while #rows > MAX_ROWS do table.remove(rows) end
    return { rows = rows, total = total }
end

-- Returns the ranking if ready; otherwise starts computing it and returns nil.
function Today.Get(settings)
    local key = Key(settings)
    local r = Today.results[key]
    if r then return r end
    if not ns.Runner:IsRunning(JOB) then
        local copy = {
            filter = settings.filter, difficulty = settings.difficulty,
            todayRaids = settings.todayRaids, todayDungeons = settings.todayDungeons,
        }
        ns.Runner:Start(JOB, function() return ComputeJob(copy) end, {
            pauseInCombat = false,
            onDone = function(res)
                wipe(Today.results) -- only the latest ranking is kept
                Today.results[key] = res
                if ns.UI and ns.UI.OnStatsReady then ns.UI.OnStatsReady() end
            end,
        })
    end
    return nil
end

function Today.IsComputing()
    return ns.Runner:IsRunning(JOB)
end

-- Inputs changed (collection or lockouts): stop a computation that would be stale.
local function Stale()
    if ns.Runner:IsRunning(JOB) then ns.Runner:Stop(JOB) end
end
ns.On("STATS_INVALIDATED", Stale)
ns.On("LOCKOUTS_CHANGED", function()
    Stale()
    if ns.UI and ns.UI.OnStatsReady then ns.UI.OnStatsReady() end
end)
