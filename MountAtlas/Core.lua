-- MountAtlas: settings, mount state, filters and counts.
-- The mount list (ns.DATA) comes from Simple Armory; collection state, localized names, icons and
-- the "how to get it" text come from C_MountJournal.

local ADDON, ns = ...
local L = ns.L

-- Source types, in menu order. Each Simple Armory subcategory is mapped to one of them.
ns.TYPES = {
    { key = "achievement", label = "Achievement" },
    { key = "raid",        label = "Raid" },
    { key = "dungeon",     label = "Dungeon" },
    { key = "reputation",  label = "Reputation and renown" },
    { key = "rare",        label = "Rare and world boss" },
    { key = "vendor",      label = "Vendor" },
    { key = "quest",       label = "Quest" },
    { key = "world",       label = "Treasure and zone" },
    { key = "pvp",         label = "PvP" },
    { key = "event",       label = "World event" },
    { key = "profession",  label = "Profession" },
    { key = "classrace",   label = "Class and race" },
    { key = "shop",        label = "Shop and promotion" },
    { key = "other",       label = "Other activities" },
}
ns.TYPE_LABEL = {}
for _, t in ipairs(ns.TYPES) do ns.TYPE_LABEL[t.key] = t.label end

ns.AVAILABILITY = {
    { key = "obtainable",   label = "Obtainable" },
    { key = "limited",      label = "Limited time" },
    { key = "unobtainable", label = "No longer obtainable" },
}

local function Defaults()
    local types = {}
    for _, t in ipairs(ns.TYPES) do types[t.key] = true end
    return {
        types = types,
        availability = { obtainable = true, limited = true, unobtainable = false },
        otherFaction = false,
        hideResale = false,
        missingOnly = false,
        favorites = {},              -- mountID -> true
        farmMaxExpansion = 8,        -- "What should I farm?" up to Shadowlands by default
        farmRares = true,            -- also world bosses and rares in "What should I farm?"
        instanceNotice = true,       -- chat message with the mounts of an instance when entering it
        minimapHidden = false,
    }
end

function ns.S() return ns.db.settings end

function ns.Print(text)
    print("|cff66ccffMountAtlas|r " .. text)
end

---------------------------------------------------------------------------
-- Mount state (cached; cleared when a mount is learned)
---------------------------------------------------------------------------

local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"
local cache = {}

-- Returns { name, icon, collected, known } for a mountID. known = false when the client does not
-- have the mount (data ahead of the game version).
function ns.Mount(m)
    local info = cache[m.id]
    if not info then
        local name, _, icon, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(m.id)
        info = {
            name = name or m.n,
            icon = icon or QUESTION_MARK,
            collected = isCollected and true or false,
            known = name ~= nil,
        }
        cache[m.id] = info
    end
    return info
end

function ns.ClearCache() wipe(cache) end

local playerFaction -- "A", "H" or nil (neutral Pandaren)

function ns.Availability(m, group)
    if m.no then return "unobtainable" end
    if group.limited then return "limited" end
    return "obtainable"
end

function ns.FactionAllowed(m)
    return not m.f or m.f == playerFaction or ns.S().otherFaction
end

-- True if the mount passes every filter except "only missing" (which only hides icons, the
-- counts stay the same).
function ns.Visible(m, sub, group)
    local s = ns.S()
    if not s.types[sub.type] then return false end
    if not s.availability[ns.Availability(m, group)] then return false end
    if not ns.FactionAllowed(m) then return false end
    if m.rs and s.hideResale and not ns.Mount(m).collected then return false end
    return true
end

---------------------------------------------------------------------------
-- Counts: { c = collected, t = total }, each mount counted once
---------------------------------------------------------------------------

local function CountInto(counter, seen, sub, group)
    for _, m in ipairs(sub.mounts) do
        if not seen[m.id] and ns.Visible(m, sub, group) then
            seen[m.id] = true
            counter.t = counter.t + 1
            if ns.Mount(m).collected then counter.c = counter.c + 1 end
        end
    end
end

function ns.CountSub(sub, group)
    local counter = { c = 0, t = 0 }
    CountInto(counter, {}, sub, group)
    return counter
end

function ns.CountGroup(group)
    local counter, seen = { c = 0, t = 0 }, {}
    for _, sub in ipairs(group.subs) do CountInto(counter, seen, sub, group) end
    return counter
end

function ns.CountAll()
    local counter, seen = { c = 0, t = 0 }, {}
    for _, group in ipairs(ns.DATA) do
        for _, sub in ipairs(group.subs) do CountInto(counter, seen, sub, group) end
    end
    return counter
end

function ns.Percent(counter)
    if not counter or counter.t == 0 then return nil end
    return counter.c / counter.t * 100
end

---------------------------------------------------------------------------
-- Names shown in the window
---------------------------------------------------------------------------

function ns.GroupName(group)
    if group.expansion then
        return _G["EXPANSION_NAME" .. group.expansion] or group.name
    end
    return L[group.name]
end

function ns.SubName(sub) return L[sub.name] end

---------------------------------------------------------------------------
-- Mounts in the journal that Simple Armory does not list yet (new patch, for example).
-- They are grouped by the game's own source type.
---------------------------------------------------------------------------

local GAME_SOURCE_TYPES = {
    [1] = "world", [2] = "quest", [3] = "vendor", [4] = "profession", [6] = "achievement",
    [7] = "event", [8] = "shop", [9] = "shop", [10] = "shop", [11] = "world", [12] = "shop",
}

local function AddUnlisted()
    local listed = {}
    for _, group in ipairs(ns.DATA) do
        for _, sub in ipairs(group.subs) do
            for _, m in ipairs(sub.mounts) do listed[m.id] = true end
        end
    end
    local byType = {}
    for _, id in ipairs(C_MountJournal.GetMountIDs()) do
        if not listed[id] then
            local name, _, _, _, _, sourceType, _, _, _, shouldHideOnChar, isCollected = C_MountJournal.GetMountInfoByID(id)
            if name and (isCollected or not shouldHideOnChar) then
                local kind = GAME_SOURCE_TYPES[sourceType] or "other"
                byType[kind] = byType[kind] or {}
                table.insert(byType[kind], { id = id, n = name })
            end
        end
    end
    local subs = {}
    for _, t in ipairs(ns.TYPES) do
        if byType[t.key] then
            subs[#subs + 1] = { name = t.label, type = t.key, mounts = byType[t.key] }
        end
    end
    if #subs > 0 then
        table.insert(ns.DATA, { name = "Not in Simple Armory", subs = subs })
    end
end

---------------------------------------------------------------------------
-- Lookup and shared texts
---------------------------------------------------------------------------

local lookup -- mountID -> { mount, sub, group } (first place it is listed)

function ns.Lookup(mountID)
    if not lookup then
        lookup = {}
        for _, group in ipairs(ns.DATA) do
            for _, sub in ipairs(group.subs) do
                for _, m in ipairs(sub.mounts) do
                    if not lookup[m.id] then lookup[m.id] = { mount = m, sub = sub, group = group } end
                end
            end
        end
    end
    return lookup[mountID]
end

function ns.AttemptsText(attempts)
    return string.format(L["%d attempts"], attempts or 0)
end

-- Shown when the boss is up for this character: "Good luck! 37 attempts so far".
function ns.LuckText(attempts)
    if (attempts or 0) == 0 then return L["Good luck! First attempt"] end
    return string.format(L["Good luck! %d attempts so far"], attempts)
end

---------------------------------------------------------------------------
-- Favorites and waypoints
---------------------------------------------------------------------------

function ns.IsFavorite(mountID) return ns.S().favorites[mountID] == true end

function ns.ToggleFavorite(mountID)
    ns.S().favorites[mountID] = (not ns.IsFavorite(mountID)) or nil
end

-- Sets a waypoint to where the mount drops (coordinates from Rarity): TomTom's arrow if TomTom is
-- loaded, otherwise the game's own map pin. Returns false when there is nowhere to point to.
function ns.Waypoint(mountID)
    local loc = ns.Rarity.Location(mountID)
    if not loc then return false end
    local title = ns.Mount({ id = mountID, n = "" }).name
    if TomTom and TomTom.AddWaypoint then
        TomTom:AddWaypoint(loc.m, loc.x, loc.y, { title = title, from = "MountAtlas" })
        return true
    end
    if C_Map.CanSetUserWaypointOnMap(loc.m) then
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(loc.m, loc.x, loc.y))
        C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        return true
    end
    ns.Print(L["That place cannot have a map pin (it is inside an instance). Install TomTom for an arrow."])
    return true
end

-- Exact place: waypoint. Only the zone known (roaming rares…): open the world map on that zone.
function ns.ShowOnMap(mountID)
    if ns.Rarity.Location(mountID) then return ns.Waypoint(mountID) end
    local zone = ns.Rarity.Zone(mountID)
    if zone and OpenWorldMap then
        OpenWorldMap(zone)
        return true
    end
    return false
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("NEW_MOUNT_ADDED")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        MountAtlasDB = MountAtlasDB or {}
        ns.db = MountAtlasDB
        local defaults = Defaults()
        ns.db.settings = ns.db.settings or {}
        local s = ns.db.settings
        for k, v in pairs(defaults) do
            if s[k] == nil then s[k] = v end
        end
        -- New source types or availability classes added in later versions start enabled.
        for k, v in pairs(defaults.types) do if s.types[k] == nil then s.types[k] = v end end
        for k, v in pairs(defaults.availability) do if s.availability[k] == nil then s.availability[k] = v end end
        ns.db.chars = ns.db.chars or {} -- per character kills for the farm list (Farm.lua)
    elseif event == "PLAYER_LOGIN" then
        local faction = UnitFactionGroup("player")
        playerFaction = (faction == "Alliance" and "A") or (faction == "Horde" and "H") or nil
        AddUnlisted()
        lookup = nil
        ns.minimapButton = ns.CreateMinimapButton({
            name = "MountAtlasMinimapButton",
            icon = "Interface\\Icons\\Ability_Mount_RidingHorse",
            settings = ns.S(),
            angle = 225,
            onClick = function() ns.UI.Toggle() end,
            onEnter = function(tooltip) ns.SummaryTooltip(tooltip) end,
        })
    elseif event == "NEW_MOUNT_ADDED" then
        ns.ClearCache()
        if ns.UI then ns.UI.Refresh() end
    end
end)

---------------------------------------------------------------------------
-- Slash command and addon compartment
---------------------------------------------------------------------------

SLASH_MOUNTATLAS1 = "/matlas"
SLASH_MOUNTATLAS2 = "/mountatlas"
SlashCmdList["MOUNTATLAS"] = function(text)
    text = strtrim(text or "")
    if text == "help" then
        ns.Print(L["Commands: /matlas (window) | /matlas <text> (search) | /matlas semana | /matlas minimap | /matlas logros"])
    elseif text == "logros" or text == "achievements" then
        ns.Achievements.Build()
        if ns.Achievements.IsReady() then
            ns.Print(string.format(L["Achievements linked to a mount: %d"], ns.Achievements.Count()))
        else
            ns.Print(L["Looking up achievements…"])
        end
    elseif text == "semana" or text == "week" then
        ns.UI.ShowWeek()
    elseif text == "minimap" then
        ns.S().minimapHidden = not ns.S().minimapHidden
        ns.minimapButton:Refresh()
    elseif text ~= "" then
        ns.UI.Show(text)
    else
        ns.UI.Toggle()
    end
end

function MountAtlas_OnAddonCompartmentClick()
    ns.UI.Toggle()
end

local MAX_FAVORITES_IN_TOOLTIP = 15

-- Favorites still missing: type, drop chance and whether this character already killed the boss.
-- Free ones first, then killed, then the ones without lockout data.
local function AddFavorites(tooltip)
    local rows, seen = {}, {}
    for _, group in ipairs(ns.DATA) do
        for _, sub in ipairs(group.subs) do
            for _, m in ipairs(sub.mounts) do
                if ns.IsFavorite(m.id) and not seen[m.id] then
                    seen[m.id] = true
                    local info = ns.Mount(m)
                    if not info.collected then
                        local defeated = ns.Rarity.Defeated(m.id)
                        local order = (defeated == false and 1) or (defeated == true and 2) or 3
                        rows[#rows + 1] = { m = m, sub = sub, info = info, defeated = defeated, order = order }
                    end
                end
            end
        end
    end
    tooltip:AddLine(" ")
    if next(seen) == nil then
        tooltip:AddLine(L["No favorites yet. Right-click a mount to add it."], 0.6, 0.6, 0.6, true)
        return
    end
    if #rows == 0 then
        tooltip:AddLine(L["You have all your favorites."], 0.25, 0.85, 0.30)
        return
    end
    table.sort(rows, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.info.name < b.info.name
    end)
    tooltip:AddLine(L["Favorites you are missing"], 1, 0.82, 0)
    for i, r in ipairs(rows) do
        if i > MAX_FAVORITES_IN_TOOLTIP then
            tooltip:AddLine(string.format(L["  …and %d more"], #rows - MAX_FAVORITES_IN_TOOLTIP), 0.6, 0.6, 0.6)
            break
        end
        local left = "|T" .. r.info.icon .. ":14|t " .. r.info.name .. "  |cff909090" .. L[ns.TYPE_LABEL[r.sub.type]] .. "|r"
        local parts = {}
        local chance = ns.Rarity.Chance(r.m.id)
        if chance and ns.ChanceText then parts[#parts + 1] = "|cffd0d0d0" .. ns.ChanceText(chance) .. "|r" end
        if r.defeated ~= nil then
            local weekly = ns.Farm.IsWeekly(r.sub, ns.Rarity.Item(r.m.id))
            if r.defeated then
                parts[#parts + 1] = "|cffff4040" .. (weekly and L["Killed this week"] or L["Killed today"]) .. "|r"
            else
                parts[#parts + 1] = "|cff40d050" .. L["Available"] .. "|r"
            end
        end
        tooltip:AddDoubleLine(left, table.concat(parts, "  "), 1, 1, 1, 1, 1, 1)
    end
end

function ns.SummaryTooltip(tooltip)
    tooltip:AddLine("MountAtlas")
    tooltip:AddLine(L["Click to open or close the window."], 1, 1, 1)
    local total = ns.CountAll()
    if total.t > 0 then
        tooltip:AddLine(string.format("%s: %d%% (%d/%d)", L["Total"], math.floor(ns.Percent(total)), total.c, total.t), 0.8, 0.8, 0.8)
    end
    AddFavorites(tooltip)
end

function MountAtlas_OnAddonCompartmentEnter(_, button)
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    ns.SummaryTooltip(GameTooltip)
    GameTooltip:Show()
end

function MountAtlas_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
