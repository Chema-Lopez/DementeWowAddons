-- MountAtlas: chat message when entering an instance, with the mounts you are missing that drop
-- there (drop chance, difficulties, attempts and whether this character already killed the boss).
-- The instance of each mount comes from Rarity's coordinates, matched through the Adventure Guide
-- (C_EncounterJournal.GetInstanceForGameMap), so it only covers mounts Rarity knows.

local ADDON, ns = ...
local L = ns.L

local lastInstance

local function StatusText(e)
    local attempts = ns.Rarity.Attempts(e.mount.id) or 0
    local defeated = ns.Rarity.Defeated(e.mount.id)
    if defeated == true then
        local weekly = ns.Farm.IsWeekly(e.sub, ns.Rarity.Item(e.mount.id))
        return "|cffff4040" .. (weekly and L["Already killed this week"] or L["Already killed today"]) .. "|r |cff909090(" .. ns.AttemptsText(attempts) .. ")|r"
    elseif defeated == false then
        return "|cff40d050" .. ns.LuckText(attempts) .. "|r"
    end
    return "|cff909090" .. ns.AttemptsText(attempts) .. "|r"
end

local function Announce()
    if not (ns.db and ns.S().instanceNotice and ns.Rarity.IsAvailable()) then return end
    if not IsInInstance() then
        lastInstance = nil
        return
    end
    local instanceID = select(8, GetInstanceInfo())
    if instanceID == lastInstance then return end
    local uiMapID = C_Map.GetBestMapForUnit("player")
    local journalID = uiMapID and C_EncounterJournal.GetInstanceForGameMap(uiMapID)
    if not journalID then return end
    lastInstance = instanceID

    local rows = {}
    for mountID in pairs(ns.Rarity.All()) do
        if ns.Rarity.JournalInstance(mountID) == journalID then
            local e = ns.Lookup(mountID)
            if e and not ns.Mount(e.mount).collected and ns.FactionAllowed(e.mount) then rows[#rows + 1] = e end
        end
    end
    if #rows == 0 then return end
    table.sort(rows, function(a, b) return (ns.Rarity.Chance(a.mount.id) or 0) > (ns.Rarity.Chance(b.mount.id) or 0) end)

    ns.Print(L["Mounts you are missing here:"])
    for _, e in ipairs(rows) do
        local info = ns.Mount(e.mount)
        local chance = ns.Rarity.Chance(e.mount.id)
        local parts = { "|T" .. info.icon .. ":14|t " .. info.name }
        if chance and ns.ChanceText then parts[#parts + 1] = ns.ChanceText(chance) end
        local difficulties = ns.Rarity.Difficulties(e.mount.id)
        if difficulties then parts[#parts + 1] = "|cff909090" .. difficulties .. "|r" end
        parts[#parts + 1] = StatusText(e)
        print("   " .. table.concat(parts, " · "))
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:SetScript("OnEvent", function()
    C_Timer.After(3, Announce) -- the map and Rarity's lockouts take a moment after loading
end)
