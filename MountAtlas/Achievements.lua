-- MountAtlas: achievement progress for mounts that are achievement rewards.
-- An achievement is linked to a mount in two ways:
--   1. its reward item (C_AchievementInfo.GetRewardItemID) is a mount item (GetMountFromItem);
--   2. otherwise, its reward text ("Reward: Plagued Proto-Drake") contains the name of one of the
--      mounts Simple Armory lists under an achievement subcategory (longest name wins). Many old
--      achievements grant the mount directly and have no reward item.
-- The index is built once per session, one achievement category per frame so the game does not
-- stutter, and the window is refreshed when it is ready.

local ADDON, ns = ...
local L = ns.L

local Achievements = {}
ns.Achievements = Achievements

local byMount       -- mountID -> achievementID (nil until built)
local building = false

-- Lower-case names of the achievement mounts, to search the reward texts.
local function AchievementMountNames()
    local names = {}
    for _, group in ipairs(ns.DATA) do
        for _, sub in ipairs(group.subs) do
            if sub.type == "achievement" then
                for _, m in ipairs(sub.mounts) do
                    local info = ns.Mount(m)
                    if info.known then names[m.id] = info.name:lower() end
                end
            end
        end
    end
    return names
end

local function MountFromRewardText(text, names)
    if not text or text == "" then return nil end
    text = text:lower()
    local best, bestLength
    for mountID, name in pairs(names) do
        if #name > (bestLength or 3) and text:find(name, 1, true) then
            best, bestLength = mountID, #name
        end
    end
    return best
end

function Achievements.Build()
    if byMount or building then return end
    building = true
    local result = {}
    local names = AchievementMountNames()
    local categories = GetCategoryList() or {}
    local i = 0
    local ticker
    ticker = C_Timer.NewTicker(0, function()
        i = i + 1
        local category = categories[i]
        if not category then
            ticker:Cancel()
            byMount, building = result, false
            if ns.UI then ns.UI.Refresh() end
            return
        end
        local total = GetCategoryNumAchievements(category, true) or 0
        for index = 1, total do
            local achievementID = GetAchievementInfo(category, index)
            -- Earlier steps of a series are not listed in the category, only the newest one.
            while achievementID do
                local itemID = C_AchievementInfo.GetRewardItemID(achievementID)
                local mountID = itemID and C_MountJournal.GetMountFromItem(itemID)
                if not mountID then
                    local rewardText = select(11, GetAchievementInfo(achievementID))
                    mountID = MountFromRewardText(rewardText, names)
                end
                if mountID and not result[mountID] then result[mountID] = achievementID end
                achievementID = GetPreviousAchievement(achievementID)
            end
        end
    end)
end

function Achievements.IsReady() return byMount ~= nil end

function Achievements.Count()
    local n = 0
    for _ in pairs(byMount or {}) do n = n + 1 end
    return n
end

function Achievements.For(mountID)
    return byMount and byMount[mountID]
end

-- Adds the achievement and its criteria to the tooltip.
function Achievements.AddToTooltip(tooltip, mountID)
    local achievementID = Achievements.For(mountID)
    if not achievementID then return false end
    local _, name, _, completed = GetAchievementInfo(achievementID)
    if not name then return false end
    tooltip:AddLine(" ")
    tooltip:AddLine(string.format(L["Achievement: %s"], name), 1, 0.82, 0)
    if completed then
        tooltip:AddLine(L["Completed"], 0.25, 0.85, 0.30)
        return true
    end
    local numCriteria = GetAchievementNumCriteria(achievementID) or 0
    local done = 0
    for i = 1, numCriteria do
        local text, _, criteriaDone, quantity, required = GetAchievementCriteriaInfo(achievementID, i)
        if criteriaDone then done = done + 1 end
        if i <= 12 then
            local line = text or ""
            if required and required > 1 then line = string.format("%s (%d/%d)", line, quantity or 0, required) end
            if criteriaDone then
                tooltip:AddLine("  |TInterface\\RaidFrame\\ReadyCheck-Ready:12|t " .. line, 0.6, 0.6, 0.6)
            else
                tooltip:AddLine("  |TInterface\\RaidFrame\\ReadyCheck-NotReady:12|t " .. line, 1, 1, 1)
            end
        end
    end
    if numCriteria > 12 then
        tooltip:AddLine(string.format(L["  …and %d more"], numCriteria - 12), 0.6, 0.6, 0.6)
    end
    if numCriteria > 0 then
        tooltip:AddLine(string.format(L["Progress: %d/%d"], done, numCriteria), 1, 0.82, 0)
    end
    return true
end

function Achievements.Open(mountID)
    local achievementID = Achievements.For(mountID)
    if achievementID then ShowAchievementFrameForAchievement(achievementID) end
end
