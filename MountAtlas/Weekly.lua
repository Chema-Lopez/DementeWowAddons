-- MountAtlas: data for the weekly summary.
--   - Mounts learned, with date and character (NEW_MOUNT_ADDED), kept account-wide.
--   - Rarity's attempt counts at the start of the week, so this week's attempts can be told apart
--     from the total. The first week only counts from the moment MountAtlas first saw them.

local ADDON, ns = ...

local Week = {}
ns.Week = Week

local WEEK = 7 * 24 * 3600
local MAX_HISTORY = 300

-- Time of the last weekly reset.
function Week.Start()
    return time() + (C_DateAndTime.GetSecondsUntilWeeklyReset() or 0) - WEEK
end

local function Snapshot()
    local start = Week.Start()
    local week = ns.db.week
    if week and week.start and math.abs(week.start - start) < 3600 then return end
    week = { start = start, attempts = {} }
    for mountID, item in pairs(ns.Rarity.All()) do
        week.attempts[mountID] = tonumber(item.attempts) or 0
    end
    ns.db.week = week
end

function Week.AttemptsThisWeek(mountID)
    local now = ns.Rarity.Attempts(mountID) or 0
    local week = ns.db.week
    if not week then return 0 end
    local base = week.attempts[mountID]
    if base == nil then
        week.attempts[mountID] = now -- first time seen this week
        return 0
    end
    return math.max(0, now - base)
end

-- Mounts learned since the last reset, newest first: { id, t, c (character key), cl (class) }.
function Week.Learned()
    local start, out = Week.Start(), {}
    for _, e in ipairs(ns.db.history or {}) do
        if e.t >= start then out[#out + 1] = e end
    end
    table.sort(out, function(a, b) return a.t > b.t end)
    return out
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("NEW_MOUNT_ADDED")
events:SetScript("OnEvent", function(_, event, mountID)
    if not ns.db then return end
    if event == "PLAYER_LOGIN" then
        C_Timer.After(3, Snapshot) -- Rarity's data must be loaded
    elseif event == "NEW_MOUNT_ADDED" and mountID then
        ns.db.history = ns.db.history or {}
        local _, class = UnitClass("player")
        table.insert(ns.db.history, { id = mountID, t = time(), c = ns.Farm.CharKey(), cl = class })
        while #ns.db.history > MAX_HISTORY do table.remove(ns.db.history, 1) end
    end
end)
