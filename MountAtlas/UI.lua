-- MountAtlas: main window, laid out like Simple Armory.
--   Left: "All" and every group (expansions and themes), each with its completion bar.
--   Top: source type and availability filters, options, "only missing" and search.
--   Right: each subcategory of the selected group as a header with its bar and a grid of icons
--   (collected in colour, missing greyed out). The tooltip says how to get the mount.
--   Extra views: "What should I farm?" (Farm.lua), the weekly summary (Weekly.lua) and favorites.

local ADDON, ns = ...
local L = ns.L

local UI = {}
ns.UI = UI

local FRAME_W, FRAME_H = 1000, 640
local NAV_W = 220
local ICON, ICON_GAP = 36, 4

local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local WHITE = "Interface\\Buttons\\WHITE8X8"

local ALL = 0
local FARM = -1
local FAVORITES = -2
local WEEK = -3
local EVENT = -4
local EventRows -- defined with the event view, used by the navigation

local ICON_HAVE = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t"
local ICON_MISSING = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14|t"

local frame, navContent, mainScroll, mainContent
local typesButton, availabilityButton, optionsButton, missingCheck, searchBox, statusText
local selected = FARM -- FARM, FAVORITES, EVENT, WEEK or an index in ns.DATA
local searchText = ""

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function S() return ns.S() end

local function ProgressColor(p)
    if p >= 90 then return 0.25, 0.75, 0.30 end
    if p >= 50 then return 0.85, 0.70, 0.20 end
    return 0.80, 0.25, 0.25
end

local function PercentString(counter)
    local p = ns.Percent(counter)
    if not p then return "–" end
    return string.format("%d%%  (%d/%d)", math.floor(p), counter.c, counter.t)
end

-- "12%", "1.5%", "0.25%" style drop chance.
local function ChanceText(chance)
    local p = chance * 100
    if p >= 10 then return string.format("%d%%", math.floor(p + 0.5)) end
    if p >= 1 then return (string.format("%.1f", p):gsub("%.0$", "")) .. "%" end
    return (string.format("%.2f", p):gsub("0$", "")) .. "%"
end
ns.ChanceText = ChanceText

local function TypesLabel()
    local on = 0
    for _, t in ipairs(ns.TYPES) do if S().types[t.key] then on = on + 1 end end
    if on == #ns.TYPES then return L["Sources: all"] end
    return string.format(L["Sources: %d of %d"], on, #ns.TYPES)
end

---------------------------------------------------------------------------
-- Widget pools (widgets are reused on every refresh)
---------------------------------------------------------------------------

local function NewPool(create)
    return { items = {}, used = 0, create = create }
end

local function Acquire(pool, parent)
    pool.used = pool.used + 1
    local w = pool.items[pool.used]
    if not w then
        w = pool.create(parent)
        pool.items[pool.used] = w
    end
    w:ClearAllPoints()
    w:Show()
    return w
end

local function ResetPool(pool) pool.used = 0 end

local function HideUnused(pool)
    for i = pool.used + 1, #pool.items do pool.items[i]:Hide() end
end

local function CreateBar(parent, width, height)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetSize(width, height)
    bar:SetStatusBarTexture(BAR_TEXTURE)
    bar:SetMinMaxValues(0, 1)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetTexture(WHITE)
    bar.bg:SetVertexColor(0, 0, 0, 0.55)
    bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.text:SetPoint("CENTER")
    return bar
end

local function SetBar(bar, counter)
    local p = ns.Percent(counter)
    if p then
        bar:SetValue(counter.c / counter.t)
        bar:SetStatusBarColor(ProgressColor(p))
    else
        bar:SetValue(0)
    end
    bar.text:SetText(PercentString(counter))
end

---------------------------------------------------------------------------
-- Left navigation: groups
---------------------------------------------------------------------------

local navPool = NewPool(function(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(NAV_W - 24, 40)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetTexture(WHITE)
    b:SetHighlightTexture(WHITE)
    b:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.08)
    b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.name:SetPoint("TOPLEFT", 8, -5)
    b.name:SetPoint("RIGHT", -8, 0)
    b.name:SetJustifyH("LEFT")
    b.name:SetWordWrap(false)
    b.bar = CreateBar(b, NAV_W - 40, 12)
    b.bar:SetPoint("BOTTOMLEFT", 8, 5)
    return b
end)

local function RefreshNav()
    ResetPool(navPool)
    local y = 0
    local function Add(index, name, counter)
        local b = Acquire(navPool, navContent)
        b:SetPoint("TOPLEFT", 4, -y)
        b.name:SetText(name)
        b.bg:SetVertexColor(1, 0.82, 0, (index == selected and searchText == "") and 0.18 or 0.04)
        b:SetHeight(counter and 40 or 30)
        b.bar:SetShown(counter ~= nil)
        if counter then SetBar(b.bar, counter) end
        b:SetScript("OnClick", function()
            selected = index
            searchBox:SetText("") -- also clears searchText through OnTextChanged
            UI.Refresh()
            mainScroll:SetVerticalScroll(0)
        end)
        y = y + (counter and 44 or 34)
    end
    Add(FARM, "|TInterface\\Icons\\INV_Misc_Map_01:16|t " .. L["What should I farm?"])
    Add(FAVORITES, "|A:PetJournal-FavoritesIcon:16:16|a " .. L["Favorites"])
    if selected == EVENT or #EventRows() > 0 then
        Add(EVENT, "|TInterface\\Icons\\INV_Misc_Bone_Skull_02:16|t " .. L["Holiday event on now"])
    end
    for index, group in ipairs(ns.DATA) do
        local counter = ns.CountGroup(group)
        -- Groups with nothing left after the filters are hidden, except the selected one.
        if counter.t > 0 or index == selected then
            Add(index, ns.GroupName(group), counter)
        end
    end
    Add(WEEK, "|TInterface\\Icons\\Spell_Nature_TimeStop:16|t " .. L["Weekly summary"])
    HideUnused(navPool)
    navContent:SetHeight(math.max(1, y))
end

---------------------------------------------------------------------------
-- Main area
---------------------------------------------------------------------------

local headerPool = NewPool(function(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(1, 26)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.text:SetPoint("LEFT", 2, 0)
    f.text:SetJustifyH("LEFT")
    f.bar = CreateBar(f, 220, 14)
    f.bar:SetPoint("RIGHT", -6, 0)
    f.text:SetPoint("RIGHT", f.bar, "LEFT", -8, 0)
    f.line = f:CreateTexture(nil, "ARTWORK")
    f.line:SetTexture(WHITE)
    f.line:SetVertexColor(1, 0.82, 0, 0.25)
    f.line:SetHeight(1)
    f.line:SetPoint("BOTTOMLEFT", 0, 0)
    f.line:SetPoint("BOTTOMRIGHT", 0, 0)
    return f
end)

local textPool = NewPool(function(parent)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    return fs
end)

local function MountTooltip(button)
    local m, sub, group = button.mount, button.sub, button.group
    local info = ns.Mount(m)
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:AddLine(info.name, 1, 1, 1)
    if info.collected then
        GameTooltip:AddLine(L["Collected"], 0.25, 0.85, 0.30)
    else
        GameTooltip:AddLine(L["Not collected"], 0.90, 0.30, 0.30)
    end
    GameTooltip:AddLine(ns.GroupName(group) .. " · " .. ns.SubName(sub) .. " (" .. L[ns.TYPE_LABEL[sub.type]] .. ")", 0.6, 0.6, 0.6)

    local availability = ns.Availability(m, group)
    if availability == "unobtainable" then
        GameTooltip:AddLine(L["No longer obtainable"], 1, 0.5, 0.25)
    elseif availability == "limited" then
        GameTooltip:AddLine(L["Limited time"], 1, 0.82, 0)
    end
    if m.f == "A" then GameTooltip:AddLine(L["Alliance only"], 0.4, 0.6, 1) end
    if m.f == "H" then GameTooltip:AddLine(L["Horde only"], 1, 0.35, 0.35) end
    if m.rs then GameTooltip:AddLine(L["Also resold on the Black Market Auction House"], 0.8, 0.8, 0.8) end

    local chance = ns.Rarity.Chance(m.id)
    if chance then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(string.format(L["Drop chance: %s (1/%d)"], ChanceText(chance), math.floor(1 / chance + 0.5)), 1, 0.82, 0)
        local difficulties = ns.Rarity.Difficulties(m.id)
        if difficulties then GameTooltip:AddLine(difficulties, 0.8, 0.8, 0.8, true) end
        if not info.collected and ns.Rarity.IsEvent(m.id) and not ns.Rarity.EventActive(m.id) then
            GameTooltip:AddLine(L["The event is not on now."], 0.6, 0.6, 0.6)
            GameTooltip:AddLine(ns.AttemptsText(ns.Rarity.Attempts(m.id)), 0.8, 0.8, 0.8)
        elseif not info.collected then
            local attempts = ns.Rarity.Attempts(m.id) or 0
            local defeated = ns.Rarity.Defeated(m.id)
            local weekly = ns.Farm.IsWeekly(sub, ns.Rarity.Item(m.id))
            if defeated == true then
                GameTooltip:AddLine(weekly and L["Already killed this week on this character"] or L["Already killed today on this character"], 1, 0.25, 0.25)
                GameTooltip:AddLine(ns.AttemptsText(attempts), 0.8, 0.8, 0.8)
            elseif defeated == false then
                GameTooltip:AddLine(ns.LuckText(attempts), 0.25, 0.85, 0.30)
            else
                GameTooltip:AddLine(ns.AttemptsText(attempts), 0.8, 0.8, 0.8)
            end
            if defeated ~= nil then
                local free, killed = ns.Farm.Alts(m.id)
                if #free > 0 then GameTooltip:AddLine(L["Available on: "] .. table.concat(free, ", "), 0.8, 0.8, 0.8, true) end
                if #killed > 0 then GameTooltip:AddLine(L["Killed on: "] .. table.concat(killed, ", "), 0.8, 0.8, 0.8, true) end
            end
        end
    end

    if info.known then
        local _, description, source = C_MountJournal.GetMountInfoExtraByID(m.id)
        if source and source ~= "" then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(source, 1, 1, 1, true)
        end
        if description and description ~= "" then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(description, 0.6, 0.6, 0.6, true)
        end
        local hasAchievement = false
        if not info.collected then
            hasAchievement = ns.Achievements.AddToTooltip(GameTooltip, m.id)
            if not hasAchievement and sub.type == "achievement" then
                GameTooltip:AddLine(" ")
                if ns.Achievements.IsReady() then
                    GameTooltip:AddLine(L["I could not find the achievement for this mount."], 0.6, 0.6, 0.6)
                else
                    GameTooltip:AddLine(L["Looking up achievements…"], 0.6, 0.6, 0.6)
                end
            end
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(L["Click: show it in the Mount Journal"], 0.5, 0.8, 1)
        GameTooltip:AddLine(L["Right-click: add to or remove from favorites"], 0.5, 0.8, 1)
        if ns.Rarity.Location(m.id) then
            GameTooltip:AddLine(L["Shift-click: set a waypoint"], 0.5, 0.8, 1)
        elseif ns.Rarity.Zone(m.id) then
            GameTooltip:AddLine(L["Shift-click: show the zone on the map (it has no fixed spot)"], 0.5, 0.8, 1)
        end
        if hasAchievement then GameTooltip:AddLine(L["Ctrl-click: open the achievement"], 0.5, 0.8, 1) end
    else
        GameTooltip:AddLine(L["Not in the game client yet."], 0.6, 0.6, 0.6)
    end
    GameTooltip:Show()
end

-- Same calls Blizzard uses to open the journal on a new mount (AlertFrameSystems.lua).
local function OpenInJournal(mountID)
    SetCollectionsJournalShown(true, COLLECTIONS_JOURNAL_TAB_INDEX_MOUNTS)
    if CollectionsJournal and CollectionsJournal:IsShown() then
        MountJournal_SelectByMountID(mountID)
    end
end

local iconPool = NewPool(function(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(ICON, ICON)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetTexture(WHITE)
    b.border:SetPoint("TOPLEFT", -1, 1)
    b.border:SetPoint("BOTTOMRIGHT", 1, -1)
    b.border:SetDrawLayer("BACKGROUND")
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b.star = b:CreateTexture(nil, "OVERLAY")
    b.star:SetAtlas("PetJournal-FavoritesIcon")
    b.star:SetSize(14, 14)
    b.star:SetPoint("TOPLEFT", -3, 3)
    b.chance = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    b.chance:SetPoint("BOTTOMRIGHT", -1, 2)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnEnter", MountTooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnClick", function(self, mouseButton)
        local id = self.mount.id
        if mouseButton == "RightButton" then
            ns.ToggleFavorite(id)
            UI.Refresh()
        elseif IsShiftKeyDown() then
            ns.ShowOnMap(id)
        elseif IsControlKeyDown() then
            ns.Achievements.Open(id)
        elseif ns.Mount(self.mount).known then
            OpenInJournal(id)
        end
    end)
    return b
end)

local function MainWidth()
    return mainContent:GetWidth()
end

local function AddHeader(y, text, counter, font)
    local h = Acquire(headerPool, mainContent)
    h:SetPoint("TOPLEFT", 0, -y)
    h:SetWidth(MainWidth())
    h.text:SetFontObject(font or "GameFontNormalLarge")
    h.text:SetText(text)
    if counter then
        h.bar:Show()
        SetBar(h.bar, counter)
    else
        h.bar:Hide()
    end
    return y + 30
end

local function AddText(y, text)
    local fs = Acquire(textPool, mainContent)
    fs:SetPoint("TOPLEFT", 4, -y)
    fs:SetWidth(MainWidth() - 8)
    fs:SetText(text)
    return y + fs:GetStringHeight() + 6
end

-- entries: list of { mount, sub, group }. Returns the new y.
local function AddIcons(y, entries)
    local perRow = math.max(1, math.floor((MainWidth() + ICON_GAP) / (ICON + ICON_GAP)))
    local col = 0
    for _, e in ipairs(entries) do
        local info = ns.Mount(e.mount)
        local b = Acquire(iconPool, mainContent)
        b:SetPoint("TOPLEFT", col * (ICON + ICON_GAP) + 2, -y)
        b.mount, b.sub, b.group = e.mount, e.sub, e.group
        b.icon:SetTexture(info.icon)
        b.icon:SetDesaturated(not info.collected)
        b.icon:SetAlpha(info.collected and 1 or 0.55)
        b.star:SetShown(ns.IsFavorite(e.mount.id))
        local chance = not info.collected and ns.Rarity.Chance(e.mount.id)
        b.chance:SetText(chance and ChanceText(chance) or "")
        if info.collected then
            b.border:SetVertexColor(0.25, 0.75, 0.30, 0.9)
        elseif ns.Availability(e.mount, e.group) == "unobtainable" then
            b.border:SetVertexColor(1, 0.5, 0.25, 0.6)
        else
            b.border:SetVertexColor(0, 0, 0, 0.8)
        end
        col = col + 1
        if col >= perRow then
            col = 0
            y = y + ICON + ICON_GAP
        end
    end
    if col > 0 then y = y + ICON + ICON_GAP end
    return y + 6
end

-- Visible mounts of a subcategory, respecting "only missing".
local function SubEntries(sub, group)
    local entries, seen = {}, {}
    for _, m in ipairs(sub.mounts) do
        if not seen[m.id] and ns.Visible(m, sub, group) then
            seen[m.id] = true
            if not (S().missingOnly and ns.Mount(m).collected) then
                entries[#entries + 1] = { mount = m, sub = sub, group = group }
            end
        end
    end
    return entries
end

local function BuildGroup(y, group, withTitle)
    local shownAny = false
    if withTitle then
        local counter = ns.CountGroup(group)
        if counter.t == 0 then return y, false end
        y = AddHeader(y, ns.GroupName(group), counter)
        y = y + 4
    end
    for _, sub in ipairs(group.subs) do
        local counter = ns.CountSub(sub, group)
        if counter.t > 0 then
            local entries = SubEntries(sub, group)
            if #entries > 0 then
                shownAny = true
                y = AddHeader(y, ns.SubName(sub) .. "  |cff909090" .. L[ns.TYPE_LABEL[sub.type]] .. "|r", counter, "GameFontNormal")
                if sub.info then y = AddText(y, "|cff909090" .. sub.info .. "|r") end
                y = AddIcons(y + 2, entries)
            end
        end
    end
    return y + 8, shownAny
end

local function BuildSearch(y)
    y = AddHeader(y, string.format(L["Search: %s"], searchText))
    local needle = searchText:lower()
    local entries, seen = {}, {}
    for _, group in ipairs(ns.DATA) do
        for _, sub in ipairs(group.subs) do
            for _, m in ipairs(sub.mounts) do
                if not seen[m.id] and ns.Visible(m, sub, group) then
                    local info = ns.Mount(m)
                    if info.name:lower():find(needle, 1, true) or m.n:lower():find(needle, 1, true) then
                        seen[m.id] = true
                        if not (S().missingOnly and info.collected) then
                            entries[#entries + 1] = { mount = m, sub = sub, group = group }
                        end
                    end
                end
            end
        end
    end
    table.sort(entries, function(a, b) return ns.Mount(a.mount).name < ns.Mount(b.mount).name end)
    if #entries == 0 then return AddText(y, L["No results."]) end
    return AddIcons(y + 2, entries)
end

local farmPool = NewPool(function(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(40)
    row:SetHighlightTexture(WHITE)
    row:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.06)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(34, 34)
    row.icon:SetPoint("LEFT", 2, 0)
    row.go = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.go:SetSize(90, 22)
    row.go:SetPoint("RIGHT", -4, 0)
    row.status = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.status:SetPoint("RIGHT", row.go, "LEFT", -10, 0)
    row.status:SetWidth(110)
    row.status:SetJustifyH("RIGHT")
    row.chance = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    row.chance:SetPoint("RIGHT", row.status, "LEFT", -10, 0)
    row.chance:SetWidth(70)
    row.chance:SetJustifyH("RIGHT")
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -2)
    row.name:SetPoint("RIGHT", row.chance, "LEFT", -8, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.where = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.where:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 2)
    row.where:SetPoint("RIGHT", row.chance, "LEFT", -8, 0)
    row.where:SetJustifyH("LEFT")
    row.where:SetWordWrap(false)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnEnter", MountTooltip)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            ns.ToggleFavorite(self.mount.id)
            UI.Refresh()
        else
            OpenInJournal(self.mount.id)
        end
    end)
    return row
end)

-- One 40 px row: icon, name, a detail line, a big text (drop chance), a status and "Take me".
-- greyed = already killed this lockout: icon greyed out and "Take me" disabled.
local function AddMountRow(y, e, detail, big, status, greyed)
    local m, info = e.mount, ns.Mount(e.mount)
    local row = Acquire(farmPool, mainContent)
    row:SetPoint("TOPLEFT", 0, -y)
    row:SetWidth(MainWidth())
    row.mount, row.sub, row.group = m, e.sub, e.group
    row.icon:SetTexture(info.icon)
    row.icon:SetDesaturated(greyed and true or false)
    row.name:SetText(info.name)
    row.where:SetText(detail or "")
    row.chance:SetText(big or "")
    row.status:SetText(status or "")
    local exact = ns.Rarity.Location(m.id) ~= nil
    row.go:SetText(exact and L["Take me"] or L["Show map"])
    row.go:SetShown(not info.collected and (exact or ns.Rarity.Zone(m.id) ~= nil))
    row.go:SetEnabled(not greyed) -- already killed this lockout: nothing to go to
    row.go:SetScript("OnClick", function() ns.ShowOnMap(m.id) end)
    return y + 44
end

local function BuildFarm(y)
    local maxGroup
    for _, group in ipairs(ns.Farm.Expansions()) do
        if group.expansion == S().farmMaxExpansion then maxGroup = group end
    end
    y = AddHeader(y, L["What should I farm?"])
    if not ns.Rarity.IsAvailable() then
        return AddText(y, L["This list needs the Rarity addon (it has the drop chances). Install it and reload."])
    end
    local what = S().farmRares and L["Raid, dungeon, world boss and rare mounts you are missing"] or L["Raid and dungeon mounts you are missing"]
    y = AddText(y, "|cff909090" .. string.format(L["%s, up to %s (Options > Raid limit). Best odds first; bosses you already killed go last."], what, maxGroup and ns.GroupName(maxGroup) or "?") .. "|r")
    local list = ns.Farm.List()
    if #list == 0 then return AddText(y, L["Nothing to farm with these settings."]) end
    for _, e in ipairs(list) do
        local m = e.mount
        local where = ns.GroupName(e.group) .. " · " .. ns.SubName(e.sub)
        local difficulties = ns.Rarity.Difficulties(m.id)
        if difficulties then where = where .. " · " .. difficulties end
        local attempts = ns.AttemptsText(ns.Rarity.Attempts(m.id))
        local status
        if e.defeated then
            status = ICON_MISSING .. " |cffff4040" .. L["Killed"] .. "|r|n|cff909090" .. attempts .. "|r"
        else
            status = ICON_HAVE .. " |cff40d050" .. L["Available"] .. "|r|n|cff909090" .. attempts .. "|r"
        end
        y = AddMountRow(y, e, where, ChanceText(e.chance), status, e.defeated)
    end
    return y
end

-- Row with this character's status and which other characters have it available or killed.
local function AddLockoutRow(y, e)
    local m = e.mount
    local free, killed = ns.Farm.Alts(m.id)
    local here = ns.Rarity.Defeated(m.id)
    local detail = (#free > 0 and ("|cff40d050" .. L["Available on: "] .. "|r" .. table.concat(free, ", ")) or "")
    if #killed > 0 then
        detail = detail .. (detail ~= "" and "   " or "") .. "|cffff4040" .. L["Killed on: "] .. "|r" .. table.concat(killed, ", ")
    end
    if detail == "" then detail = ns.GroupName(e.group) .. " · " .. ns.SubName(e.sub) end
    local attempts = ns.AttemptsText(ns.Rarity.Attempts(m.id))
    local status
    if here == true then
        local weekly = ns.Farm.IsWeekly(e.sub, ns.Rarity.Item(m.id))
        status = ICON_MISSING .. " |cffff4040" .. (weekly and L["Killed this week"] or L["Killed today"]) .. "|r"
    elseif here == false then
        status = ICON_HAVE .. " |cff40d050" .. L["Available"] .. "|r"
    else
        status = ""
    end
    local chance = ns.Rarity.Chance(m.id)
    return AddMountRow(y, e, detail, chance and ChanceText(chance) or "", status .. "|n|cff909090" .. attempts .. "|r", here == true)
end

-- Missing mounts of the holiday event that is on now (empty without Rarity or with no event on).
EventRows = function()
    local rows = {}
    for mountID in pairs(ns.Rarity.All()) do
        if ns.Rarity.IsEvent(mountID) and ns.Rarity.EventActive(mountID) then
            local e = ns.Lookup(mountID)
            if e and not ns.Mount(e.mount).collected and ns.FactionAllowed(e.mount) then rows[#rows + 1] = e end
        end
    end
    table.sort(rows, function(a, b) return ns.Mount(a.mount).name < ns.Mount(b.mount).name end)
    return rows
end

local function BuildEvent(y)
    y = AddHeader(y, L["Holiday event on now"])
    local rows = EventRows()
    if #rows == 0 then return AddText(y, L["No holiday event on now, or you already have its mounts."]) end
    y = AddText(y, "|cff909090" .. L["One reward a day per character (it resets with the daily reset)."] .. "|r")
    for _, e in ipairs(rows) do y = AddLockoutRow(y, e) end
    return y
end

-- Weekly summary: what you got since the reset, this week's attempts and your favorites by character.
local function BuildWeek(y)
    y = AddHeader(y, L["Weekly summary"])
    y = AddText(y, "|cff909090" .. string.format(L["Since the weekly reset on %s."], date("%d/%m %H:%M", ns.Week.Start())) .. "|r")

    -- 1) Learned this week
    y = AddHeader(y + 4, L["Got this week"], nil, "GameFontNormal")
    local learned = ns.Week.Learned()
    if #learned == 0 then
        y = AddText(y, L["Nothing yet this week. Keep at it!"])
    end
    for _, h in ipairs(learned) do
        local e = ns.Lookup(h.id)
        if e then
            local who = h.c and (h.c:match("^[^-]+") or h.c) or "?"
            local color = h.cl and RAID_CLASS_COLORS and RAID_CLASS_COLORS[h.cl]
            if color then who = color:WrapTextInColorCode(who) end
            local detail = ns.GroupName(e.group) .. " · " .. ns.SubName(e.sub) .. " · " .. who .. " · " .. date("%d/%m %H:%M", h.t)
            local attempts = ns.Rarity.Attempts(h.id)
            y = AddMountRow(y, e, detail, ICON_HAVE, attempts and ("|cff909090" .. ns.AttemptsText(attempts) .. "|r") or "")
        end
    end

    if not ns.Rarity.IsAvailable() then
        return AddText(y + 6, L["Attempts and lockouts need the Rarity addon."])
    end

    -- 2) Attempts this week
    y = AddHeader(y + 6, L["Attempts this week"], nil, "GameFontNormal")
    local tries, total = {}, 0
    for mountID in pairs(ns.Rarity.All()) do
        local n = ns.Week.AttemptsThisWeek(mountID)
        local e = n > 0 and ns.Lookup(mountID)
        if e then
            tries[#tries + 1] = { e = e, n = n }
            total = total + n
        end
    end
    table.sort(tries, function(a, b) return a.n > b.n end)
    if #tries == 0 then
        y = AddText(y, L["No attempts recorded this week yet."])
    else
        y = AddText(y, "|cff909090" .. string.format(L["%d attempts on %d mounts."], total, #tries) .. "|r")
    end
    for _, t in ipairs(tries) do
        local m = t.e.mount
        local chance = ns.Rarity.Chance(m.id)
        local collected = ns.Mount(m).collected
        local status = string.format(L["+%d this week"], t.n) .. "|n|cff909090" .. string.format(L["Total: %d"], ns.Rarity.Attempts(m.id) or 0) .. "|r"
        if collected then status = ICON_HAVE .. " " .. status end
        y = AddMountRow(y, t.e, ns.GroupName(t.e.group) .. " · " .. ns.SubName(t.e.sub), chance and ChanceText(chance) or "", status)
    end

    -- 3) Favorites you are missing, by character
    y = AddHeader(y + 6, L["Your favorites this week"], nil, "GameFontNormal")
    local favs = {}
    for _, group in ipairs(ns.DATA) do
        for _, sub in ipairs(group.subs) do
            for _, m in ipairs(sub.mounts) do
                if ns.IsFavorite(m.id) and not ns.Mount(m).collected and ns.Rarity.Defeated(m.id) ~= nil then
                    local e = ns.Lookup(m.id)
                    if e and e.mount == m then favs[#favs + 1] = e end
                end
            end
        end
    end
    if #favs == 0 then
        return AddText(y, L["Mark raid, dungeon or rare mounts as favorites (right-click) to see them here."])
    end
    for _, e in ipairs(favs) do y = AddLockoutRow(y, e) end
    return y
end

local function BuildFavorites(y)
    y = AddHeader(y, L["Favorites"])
    local entries, seen = {}, {}
    for _, group in ipairs(ns.DATA) do
        for _, sub in ipairs(group.subs) do
            for _, m in ipairs(sub.mounts) do
                if ns.IsFavorite(m.id) and not seen[m.id] then
                    seen[m.id] = true
                    if not (S().missingOnly and ns.Mount(m).collected) then
                        entries[#entries + 1] = { mount = m, sub = sub, group = group }
                    end
                end
            end
        end
    end
    if #entries == 0 then return AddText(y, L["No favorites yet. Right-click a mount to add it."]) end
    table.sort(entries, function(a, b) return ns.Mount(a.mount).name < ns.Mount(b.mount).name end)
    return AddIcons(y + 2, entries)
end

local function RefreshMain()
    ResetPool(headerPool); ResetPool(textPool); ResetPool(iconPool); ResetPool(farmPool)
    local y = 0
    if searchText ~= "" then
        y = BuildSearch(y)
    elseif selected == FARM then
        y = BuildFarm(y)
    elseif selected == EVENT then
        y = BuildEvent(y)
    elseif selected == WEEK then
        y = BuildWeek(y)
    elseif selected == FAVORITES then
        y = BuildFavorites(y)
    elseif selected == ALL then
        local any = false
        for _, group in ipairs(ns.DATA) do
            local shown
            y, shown = BuildGroup(y, group, true)
            any = any or shown
        end
        if not any then y = AddText(y, L["Nothing to show with the current filters."]) end
    else
        local group = ns.DATA[selected]
        local shown
        y = AddHeader(y, ns.GroupName(group), ns.CountGroup(group))
        y, shown = BuildGroup(y + 4, group, false)
        if not shown then y = AddText(y, L["Nothing to show with the current filters."]) end
    end
    HideUnused(headerPool); HideUnused(textPool); HideUnused(iconPool); HideUnused(farmPool)
    mainContent:SetHeight(math.max(1, y + 10))
end

local function RefreshStatus()
    typesButton:SetText(TypesLabel())
    missingCheck:SetChecked(S().missingOnly)
    local text = L["Total"] .. ": " .. PercentString(ns.CountAll())
    if ns.DATA_DATE then
        text = text .. "   |cff909090" .. string.format(L["Mount data: Simple Armory (%s)"], ns.DATA_DATE) .. "|r"
    end
    statusText:SetText(text)
end

function UI.Refresh()
    if not (frame and frame:IsShown()) then return end
    RefreshStatus()
    RefreshNav()
    RefreshMain()
end

---------------------------------------------------------------------------
-- Filter menus
---------------------------------------------------------------------------

local function OpenTypesMenu(owner)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(L["Source"])
        root:CreateButton(L["Select all"], function()
            for _, t in ipairs(ns.TYPES) do S().types[t.key] = true end
            UI.Refresh()
            return MenuResponse.Refresh
        end)
        root:CreateButton(L["Select none"], function()
            for _, t in ipairs(ns.TYPES) do S().types[t.key] = false end
            UI.Refresh()
            return MenuResponse.Refresh
        end)
        root:CreateDivider()
        for _, t in ipairs(ns.TYPES) do
            root:CreateCheckbox(L[t.label],
                function() return S().types[t.key] end,
                function() S().types[t.key] = not S().types[t.key]; UI.Refresh() end)
        end
    end)
end

local function OpenAvailabilityMenu(owner)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(L["Availability"])
        for _, a in ipairs(ns.AVAILABILITY) do
            root:CreateCheckbox(L[a.label],
                function() return S().availability[a.key] end,
                function() S().availability[a.key] = not S().availability[a.key]; UI.Refresh() end)
        end
    end)
end

local function OpenOptionsMenu(owner)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(L["Options"])
        root:CreateCheckbox(L["Show the other faction's mounts"],
            function() return S().otherFaction end,
            function() S().otherFaction = not S().otherFaction; UI.Refresh() end)
        local resale = root:CreateCheckbox(L["Hide mounts now only sold on the Black Market"],
            function() return S().hideResale end,
            function() S().hideResale = not S().hideResale; UI.Refresh() end)
        resale:SetTooltip(function(tooltip, description)
            GameTooltip_SetTitle(tooltip, MenuUtil.GetElementText(description))
            GameTooltip_AddNormalLine(tooltip, L["Old promotion mounts (BlizzCon, collector's editions…) that can now only be bought, for a lot of gold, on the Black Market Auction House. Hidden and not counted unless you have them."])
        end)
        root:CreateCheckbox(L["World bosses and rares in \"What should I farm?\""],
            function() return S().farmRares end,
            function() S().farmRares = not S().farmRares; UI.Refresh() end)
        root:CreateCheckbox(L["Message when entering an instance"],
            function() return S().instanceNotice end,
            function() S().instanceNotice = not S().instanceNotice end)
        root:CreateCheckbox(L["Minimap button"],
            function() return not S().minimapHidden end,
            function()
                S().minimapHidden = not S().minimapHidden
                if ns.minimapButton then ns.minimapButton:Refresh() end
            end)
        local farm = root:CreateButton(L["Raid limit"])
        farm:CreateTitle(L["Raids and dungeons I can do (for \"What should I farm?\")"])
        local function IsMax(expansion) return S().farmMaxExpansion == expansion end
        local function SetMax(expansion) S().farmMaxExpansion = expansion; UI.Refresh() end
        for _, group in ipairs(ns.Farm.Expansions()) do
            farm:CreateRadio(string.format(L["Up to %s"], ns.GroupName(group)), IsMax, SetMax, group.expansion)
        end
    end)
end

---------------------------------------------------------------------------
-- Window construction
---------------------------------------------------------------------------

local function CreateScroll(name, parent, width, height)
    local scroll = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
    scroll:SetSize(width, height)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(width, 1)
    scroll:SetScrollChild(content)
    return scroll, content
end

local function CreateTopButton(text, width, onClick)
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function Build()
    frame = CreateFrame("Frame", "MountAtlasFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame.TitleText:SetText("MountAtlas")
    table.insert(UISpecialFrames, "MountAtlasFrame") -- closes with Escape

    typesButton = CreateTopButton("", 170, OpenTypesMenu)
    typesButton:SetPoint("TOPLEFT", 14, -32)
    availabilityButton = CreateTopButton(L["Availability"], 140, OpenAvailabilityMenu)
    availabilityButton:SetPoint("LEFT", typesButton, "RIGHT", 6, 0)
    optionsButton = CreateTopButton(L["Options"], 100, OpenOptionsMenu)
    optionsButton:SetPoint("LEFT", availabilityButton, "RIGHT", 6, 0)

    missingCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    missingCheck:SetSize(24, 24)
    missingCheck:SetPoint("LEFT", optionsButton, "RIGHT", 10, 0)
    missingCheck.Text:SetText(L["Only missing"])
    missingCheck:SetScript("OnClick", function(self)
        S().missingOnly = self:GetChecked() and true or false
        RefreshMain()
    end)

    searchBox = CreateFrame("EditBox", "MountAtlasSearchBox", frame, "SearchBoxTemplate")
    searchBox:SetSize(200, 20)
    searchBox:SetPoint("TOPRIGHT", -20, -33)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(40)
    -- HookScript keeps the template's own behaviour (placeholder text and clear button).
    searchBox:HookScript("OnTextChanged", function(self)
        local text = strtrim(self:GetText() or "")
        if text == searchText then return end
        searchText = text
        RefreshNav()
        RefreshMain()
        mainScroll:SetVerticalScroll(0)
    end)
    local instructions = searchBox.Instructions -- placeholder text of SearchBoxTemplate
    if type(instructions) == "table" and instructions.SetText then instructions:SetText(L["Search"]) end

    statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    statusText:SetPoint("TOPLEFT", 16, -62)
    statusText:SetPoint("TOPRIGHT", -16, -62)
    statusText:SetJustifyH("LEFT")

    local navScroll
    navScroll, navContent = CreateScroll("MountAtlasNavScroll", frame, NAV_W - 20, FRAME_H - 104)
    navScroll:SetPoint("TOPLEFT", 12, -84)

    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetTexture(WHITE)
    divider:SetVertexColor(1, 0.82, 0, 0.2)
    divider:SetWidth(1)
    divider:SetPoint("TOPLEFT", NAV_W + 8, -84)
    divider:SetPoint("BOTTOMLEFT", NAV_W + 8, 14)

    mainScroll, mainContent = CreateScroll("MountAtlasMainScroll", frame, FRAME_W - NAV_W - 56, FRAME_H - 104)
    mainScroll:SetPoint("TOPLEFT", NAV_W + 18, -84)

    frame:SetScript("OnShow", function()
        ns.Achievements.Build() -- once per session, in the background
        UI.Refresh()
    end)
end

function UI.Toggle()
    if not frame then
        Build()
        frame:Hide()
    end
    frame:SetShown(not frame:IsShown())
end

-- Opens the window with a search already typed in.
function UI.ShowWeek()
    if not frame then
        Build()
        frame:Hide()
    end
    selected = WEEK
    searchBox:SetText("")
    if frame:IsShown() then UI.Refresh() else frame:Show() end
    mainScroll:SetVerticalScroll(0)
end

function UI.Show(text)
    if not frame then
        Build()
        frame:Hide()
    end
    frame:Show()
    searchBox:SetText(text or "")
end
