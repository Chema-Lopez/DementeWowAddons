-- TransmogAtlas: main window, laid out like the Adventure Guide.
--   Left: expansions (plus "All expansions"), each with its completion bar.
--   Right: the selected expansion with its raids and dungeons as image cards, or the detail of the
--   selected instance (difficulties, encounters and the missing pieces).
--   Extra views: "What should I run?" (ranking for this week) and search results.

local ADDON, ns = ...
local L = ns.L

local UI = {}
ns.UI = UI

local FRAME_W, FRAME_H = 1040, 650
local NAV_W = 220
local CARD_W, CARD_H, CARD_GAP = 174, 96, 10
local ROW_H = 20
local MAX_ITEM_ROWS = 700

local JOURNAL_TEXTURES = "Interface\\EncounterJournal\\UI-EncounterJournalTextures"
local BAR_TEXTURE = "Interface\\TargetingFrame\\UI-StatusBar"
local WHITE = "Interface\\Buttons\\WHITE8X8"

local ICON_HAVE = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t"
local ICON_APPEARANCE = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:14|t"
local ICON_MISSING = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14|t"
local ICON_LOCK = "|TInterface\\LFGFrame\\UI-LFG-ICON-LOCK:12:12:0:0:32:32:0:28:0:28|t"
local ICON_SKULL = "|TInterface\\TargetingFrame\\UI-TargetingFrame-Skull:13|t"

local ALL_TIERS = 0
local TODAY = -1

local frame, navScroll, navContent, mainScroll, mainContent
local classButton, difficultyButton, missingCheck, scanButton, statusText, searchBox, optionsButton
local todayRaidsCheck, todayDungeonsCheck
local selectedTier, selectedInstance
local searchText = ""
local ticker

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function S() return ns.db.settings end

local function CurrentStats()
    return ns.Stats.Get(S())
end

local function ProgressColor(p)
    if p >= 90 then return 0.25, 0.75, 0.30 end
    if p >= 50 then return 0.85, 0.70, 0.20 end
    return 0.80, 0.25, 0.25
end

local function PercentString(counter)
    local p = ns.Stats.Percent(counter)
    if not p then return "–" end
    return string.format("%d%%  (%d/%d)", math.floor(p), counter.c, counter.t)
end

local function DifficultyName(difficultyID)
    return GetDifficultyInfo(difficultyID) or (L["Difficulty"] .. " " .. tostring(difficultyID))
end

local DIFFICULTY_LABELS = {
    ALL = "All difficulties",
    LFR = "Raid Finder",
    NORMAL = "Normal",
    HEROIC = "Heroic",
    MYTHIC = "Mythic",
}

-- Difficulty name for a row. Old raids whose 10- and 25-player versions drop the same pieces are
-- shown once, as "Heroic (10/25)".
local function RowDifficultyName(instanceID, difficultyID)
    if ns.Stats.Twin(instanceID, difficultyID) then
        local group = ns.Stats.GroupOf(difficultyID)
        return L[DIFFICULTY_LABELS[group] or "Normal"] .. " (10/25)"
    end
    return DifficultyName(difficultyID)
end

-- True for the 25-player twin that is folded into the 10-player row.
local function IsFoldedTwin(instanceID, difficultyID)
    local twin = ns.Stats.Twin(instanceID, difficultyID)
    return twin ~= nil and twin < difficultyID
end

local function FilterLabel()
    local f = S().filter
    if f == "ALL" then return L["Class: all"] end
    if f == "MINE" then return string.format(L["Class: mine (%s)"], ns.Classes.Name(ns.Classes.PlayerClassID())) end
    return string.format(L["Class: %s"], ns.Classes.Name(f))
end

local function DifficultyLabel()
    return L[DIFFICULTY_LABELS[S().difficulty] or DIFFICULTY_LABELS.ALL]
end

local function TierName(tier)
    if tier == ALL_TIERS then return L["All expansions"] end
    if tier == TODAY then return L["What should I run?"] end
    return ns.db.tiers[tier] or (L["Expansion"] .. " " .. tostring(tier))
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
    local p = ns.Stats.Percent(counter)
    if p then
        bar:SetValue(counter.c / counter.t)
        bar:SetStatusBarColor(ProgressColor(p))
    else
        bar:SetValue(0)
    end
    bar.text:SetText(PercentString(counter))
end

---------------------------------------------------------------------------
-- Left navigation: expansions
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

local function NavTiers()
    local tiers = {}
    for tier in pairs(ns.db.tierInstances) do tiers[#tiers + 1] = tier end
    table.sort(tiers, function(a, b) return a > b end) -- newest first, like the guide's dropdown
    return tiers
end

function UI.RefreshNav()
    if not frame then return end
    local stats = CurrentStats()
    ResetPool(navPool)
    local y = 0
    local entries = { TODAY, ALL_TIERS }
    for _, tier in ipairs(NavTiers()) do entries[#entries + 1] = tier end
    for _, tier in ipairs(entries) do
        local b = Acquire(navPool, navContent)
        b:SetPoint("TOPLEFT", 4, -y)
        b.name:SetText(TierName(tier))
        local selected = (tier == selectedTier) and not selectedInstance
        b.bg:SetVertexColor(1, 0.82, 0, selected and 0.18 or 0.04)
        b:SetHeight((tier == TODAY) and 30 or 40)
        if tier == TODAY then
            b.bar:Hide()
            b.name:SetText("|TInterface\\Icons\\INV_Misc_Map_01:16|t " .. TierName(tier))
        else
            b.bar:Show()
            local counter = stats and ((tier == ALL_TIERS) and stats.total or (stats.tiers[tier] and stats.tiers[tier].all))
            SetBar(b.bar, counter)
        end
        b:SetScript("OnClick", function()
            selectedTier = tier
            selectedInstance = nil
            UI.ClearSearch()
            UI.RefreshAll()
            mainScroll:SetVerticalScroll(0)
        end)
        y = y + ((tier == TODAY) and 34 or 44)
    end
    HideUnused(navPool)
    navContent:SetHeight(math.max(1, y))
end

---------------------------------------------------------------------------
-- Main area: generic pools
---------------------------------------------------------------------------

local headerPool = NewPool(function(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(1, 26)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.text:SetPoint("LEFT", 2, 0)
    f.bar = CreateBar(f, 260, 14)
    f.bar:SetPoint("RIGHT", -6, 0)
    f.line = f:CreateTexture(nil, "ARTWORK")
    f.line:SetTexture(WHITE)
    f.line:SetVertexColor(1, 0.82, 0, 0.25)
    f.line:SetHeight(1)
    f.line:SetPoint("BOTTOMLEFT", 0, 0)
    f.line:SetPoint("BOTTOMRIGHT", 0, 0)
    return f
end)

local cardPool = NewPool(function(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(CARD_W, CARD_H)
    b.image = b:CreateTexture(nil, "BACKGROUND")
    b.image:SetAllPoints()
    b.image:SetTexCoord(0, 0.68359375, 0, 0.7421875)
    b.border = b:CreateTexture(nil, "BORDER")
    b.border:SetAllPoints()
    b.border:SetTexture(JOURNAL_TEXTURES)
    b.border:SetTexCoord(0.00195313, 0.34179688, 0.42871094, 0.52246094)
    b:SetHighlightTexture(JOURNAL_TEXTURES)
    b:GetHighlightTexture():SetTexCoord(0.34570313, 0.68554688, 0.33300781, 0.42675781)
    b.name = b:CreateFontString(nil, "OVERLAY", "QuestTitleFontBlackShadow")
    b.name:SetPoint("TOP", 0, -12)
    b.name:SetWidth(CARD_W - 20)
    b.bar = CreateBar(b, CARD_W - 18, 13)
    b.bar:SetPoint("BOTTOM", 0, 8)
    b.lock = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.lock:SetPoint("BOTTOMLEFT", b.bar, "TOPLEFT", 0, 3)
    b.lock:SetPoint("RIGHT", -8, 0)
    b.lock:SetJustifyH("LEFT")
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end)

local rowPool = NewPool(function(parent)
    local row = CreateFrame("Button", nil, parent)
    row:SetHeight(ROW_H)
    row:SetHighlightTexture(WHITE)
    row:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.06)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    row.bar = CreateBar(row, 200, 12)
    row.bar:SetPoint("RIGHT", -6, 0)
    row:SetScript("OnEnter", function(self)
        if self.link then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self.link)
            if self.note then GameTooltip:AddLine(self.note, 1, 0.82, 0, true) end
            GameTooltip:Show()
        elseif self.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            self.tooltip(GameTooltip)
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        if self.link and IsModifiedClick() then
            HandleModifiedItemClick(self.link)
        elseif self.onClick then
            self.onClick(self)
        end
    end)
    return row
end)

local backButton

local function MainWidth()
    return mainContent:GetWidth()
end

-- opts: text, counter (bar), indent, icon, link, note, font, onClick, tooltip(GameTooltip)
local function AddRow(y, opts)
    local row = Acquire(rowPool, mainContent)
    row:SetPoint("TOPLEFT", 0, -y)
    row:SetWidth(MainWidth())
    local x = (opts.indent or 0) + 4
    if opts.icon then
        row.icon:SetTexture(opts.icon)
        row.icon:ClearAllPoints()
        row.icon:SetPoint("LEFT", x, 0)
        row.icon:Show()
        x = x + 20
    else
        row.icon:Hide()
    end
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", x, 0)
    if opts.counter ~= nil then
        row.text:SetPoint("RIGHT", row.bar, "LEFT", -8, 0)
        row.bar:Show()
        SetBar(row.bar, opts.counter or nil)
    else
        row.text:SetPoint("RIGHT", -6, 0)
        row.bar:Hide()
    end
    row.text:SetFontObject(opts.font or "GameFontHighlightSmall")
    row.text:SetText(opts.text or "")
    row.link, row.note, row.onClick, row.tooltip = opts.link, opts.note, opts.onClick, opts.tooltip
    return y + ROW_H
end

local function AddHeader(y, text, counter)
    local h = Acquire(headerPool, mainContent)
    h:SetPoint("TOPLEFT", 0, -y)
    h:SetWidth(MainWidth())
    h.text:SetText(text)
    if counter ~= nil then
        h.bar:Show()
        SetBar(h.bar, counter or nil)
    else
        h.bar:Hide()
    end
    return y + 32
end

---------------------------------------------------------------------------
-- Main area: expansion overview
---------------------------------------------------------------------------

local function CardTooltip(card)
    local entry = ns.db.instances[card.instanceID]
    local stats = CurrentStats()
    GameTooltip:SetOwner(card, "ANCHOR_RIGHT")
    GameTooltip:AddLine(entry and entry.name or "?", 1, 0.82, 0)
    local ir = stats and stats.inst[card.instanceID]
    if ir and entry then
        for _, difficultyID in ipairs(entry.diffList or {}) do
            local dr = ir.diffs[difficultyID]
            if dr and dr.total.t > 0 and not IsFoldedTwin(card.instanceID, difficultyID) then
                GameTooltip:AddDoubleLine(RowDifficultyName(card.instanceID, difficultyID), PercentString(dr.total), 1, 1, 1, 1, 1, 1)
            end
        end
    end
    local summary = ns.Lockouts.Summary(card.instanceID)
    if summary then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(ICON_LOCK .. " " .. string.format(L["Saved this week: %s"], summary), 1, 0.6, 0.4)
    end
    GameTooltip:AddLine(L["Click to see what is missing."], 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function AddCards(y, ids, stats)
    local perRow = math.max(1, math.floor((MainWidth() + CARD_GAP) / (CARD_W + CARD_GAP)))
    local col, shown = 0, 0
    for _, instanceID in ipairs(ids) do
        local entry = ns.db.instances[instanceID]
        local ir = stats and stats.inst[instanceID]
        -- Hide instances with nothing to collect for the current filters (once stats are known).
        if entry and not (ir and ir.total.t == 0) then
            local card = Acquire(cardPool, mainContent)
            card:SetPoint("TOPLEFT", col * (CARD_W + CARD_GAP), -y)
            card.instanceID = instanceID
            card.image:SetTexture(entry.buttonImage or "Interface\\EncounterJournal\\UI-EJ-DUNGEONBUTTON-Up")
            card.name:SetText(entry.name or tostring(instanceID))
            SetBar(card.bar, ir and ir.total)
            local summary = ns.Lockouts.Summary(instanceID)
            card.lock:SetText(summary and ("|cffffa070" .. ICON_LOCK .. " " .. summary .. "|r") or "")
            card:SetScript("OnEnter", CardTooltip)
            card:SetScript("OnClick", function()
                selectedInstance = instanceID
                UI.RefreshAll()
                mainScroll:SetVerticalScroll(0)
            end)
            col = col + 1
            shown = shown + 1
            if col >= perRow then
                col = 0
                y = y + CARD_H + CARD_GAP
            end
        end
    end
    if col > 0 then y = y + CARD_H + CARD_GAP end
    if shown == 0 then
        y = AddRow(y, { text = "|cff909090" .. L["Nothing to collect here with the current filters."] .. "|r" })
    end
    return y + 6
end

local function BuildAllTiers(y, stats)
    y = AddHeader(y, L["All expansions"], stats and stats.total)
    for _, tier in ipairs(NavTiers()) do
        local tr = stats and stats.tiers[tier]
        y = AddRow(y, {
            text = TierName(tier),
            font = "GameFontNormal",
            counter = tr and tr.all or false,
            indent = 4,
            onClick = function()
                selectedTier = tier
                UI.RefreshAll()
            end,
        })
        y = y + 4
    end
    return y
end

local function BuildTierOverview(y, tier, stats)
    local membership = ns.db.tierInstances[tier] or { raids = {}, dungeons = {} }
    local tr = stats and stats.tiers[tier]
    y = AddHeader(y, TierName(tier), tr and tr.all or false)
    y = y + 6
    if #membership.raids > 0 then
        y = AddHeader(y, L["Raids"], tr and tr.raids or false)
        y = AddCards(y + 4, membership.raids, stats)
    end
    if #membership.dungeons > 0 then
        y = AddHeader(y, L["Dungeons"], tr and tr.dungeons or false)
        y = AddCards(y + 4, membership.dungeons, stats)
    end
    return y
end

---------------------------------------------------------------------------
-- Main area: instance detail
---------------------------------------------------------------------------

-- Item data loader. Item names are only available once the client has cached the item. We ask
-- for every item of the current view with Item:ContinueOnItemLoad and redraw (debounced) as they
-- arrive, showing a "loading" line meanwhile.
local loadingItems = {}  -- itemID -> true while a load request is pending
local refreshQueued = false

local function QueueRefresh()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.3, function()
        refreshQueued = false
        if frame and frame:IsShown() and selectedInstance then UI.RefreshMain() end
    end)
end

-- Requests the given items and returns how many are still not cached.
local function EnsureItemsLoaded(itemIDs)
    local missing = 0
    for _, itemID in ipairs(itemIDs) do
        if not C_Item.IsItemDataCachedByID(itemID) then
            missing = missing + 1
            if not loadingItems[itemID] then
                loadingItems[itemID] = true
                Item:CreateFromItemID(itemID):ContinueOnItemLoad(function()
                    loadingItems[itemID] = nil
                    QueueRefresh()
                end)
            end
        end
    end
    return missing
end

local function ItemRowOptions(sourceID, indent)
    local meta = ns.db.src[sourceID]
    local itemID = meta and meta.i
    local info = C_TransmogCollection.GetAppearanceSourceInfo(sourceID)
    local link = info and info.itemLink
    local linkName = link and link:match("%[(.-)%]")
    local text
    if linkName and linkName ~= "" then
        text = link -- links already carry the quality color
    else
        local name = itemID and C_Item.GetItemNameByID(itemID)
        text = name or ("|cff909090" .. L["Loading…"] .. " (" .. tostring(itemID or sourceID) .. ")|r")
    end
    local status = ns.Stats.Status(sourceID)
    local mark = (status == 2 and ICON_HAVE) or (status == 1 and ICON_APPEARANCE) or ICON_MISSING
    local note = (status == 1) and L["You have this look from another item, but not this exact piece."] or nil
    return { text = mark .. " " .. text, icon = info and info.icon, indent = indent, link = link, note = note }
end

local function BuildInstanceDetail(y, instanceID, stats)
    local entry = ns.db.instances[instanceID]
    if not entry then return AddRow(y, { text = L["Unknown instance."] }) end
    local ir = stats and stats.inst[instanceID]
    local classID = ns.Stats.ResolveClass(S().filter)
    local difficultyFilter, missingOnly = S().difficulty, S().missingOnly

    y = AddHeader(y, entry.name or tostring(instanceID), ir and ir.total or false)

    -- First pass: which items will be listed, so they can be loaded before drawing names.
    local wanted, wantedSeen = {}, {}
    for _, difficultyID in ipairs(entry.diffList or {}) do
        local d = entry.diffs[difficultyID]
        if d and d.done and ns.Stats.DifficultyAllowed(difficultyID, difficultyFilter) then
            for _, list in pairs(d.enc) do
                for _, sourceID in ipairs(list) do
                    local meta = ns.db.src[sourceID]
                    if meta and meta.i and not wantedSeen[meta.i] and ns.Stats.Usable(sourceID, classID)
                        and not (missingOnly and ns.Stats.IsCollected(sourceID)) then
                        wantedSeen[meta.i] = true
                        wanted[#wanted + 1] = meta.i
                    end
                end
            end
        end
    end
    y = AddRow(y, { text = string.format("|cffa0a0a0%s %s   %s %s   %s %s|r",
        ICON_HAVE, L["you have the piece"], ICON_APPEARANCE, L["you have the look from another piece"], ICON_MISSING, L["missing"]) })
    local stillLoading = EnsureItemsLoaded(wanted)
    if stillLoading > 0 then
        y = AddRow(y, { text = "|cffffd040" .. string.format(L["Loading items… (%d left)"], stillLoading) .. "|r", font = "GameFontNormal" })
    end

    local itemRows = 0
    local anyDifficulty = false
    for _, difficultyID in ipairs(entry.diffList or {}) do
        if ns.Stats.DifficultyAllowed(difficultyID, difficultyFilter) and not IsFoldedTwin(instanceID, difficultyID) then
            anyDifficulty = true
            local d = entry.diffs[difficultyID]
            local dr = ir and ir.diffs[difficultyID]
            if not (d and d.done) then
                y = AddRow(y, { text = DifficultyName(difficultyID) .. "  |cff909090" .. L["(not scanned yet)"] .. "|r", font = "GameFontNormal" })
            elseif not (dr and dr.total.t == 0) then
                y = y + 6
                local save = ns.Lockouts.Get(instanceID, difficultyID)
                local label = RowDifficultyName(instanceID, difficultyID)
                if save then
                    label = label .. "   |cffffa070" .. ICON_LOCK .. " " .. string.format(L["saved %d/%d · resets in %s"],
                        save.k, save.n, SecondsToTime(math.max(0, save.expires - time()), true, false, 2)) .. "|r"
                end
                y = AddRow(y, {
                    text = label, font = "GameFontNormalLarge", counter = dr and dr.total or false,
                    tooltip = function(tooltip) UI.CharactersTooltip(tooltip, instanceID, difficultyID) end,
                })
                -- Encounters in guide order, then anything without a known encounter.
                local order, listed = {}, {}
                for _, encounterID in ipairs(entry.encOrder or {}) do
                    if d.enc[encounterID] then order[#order + 1] = encounterID; listed[encounterID] = true end
                end
                for encounterID in pairs(d.enc) do
                    if not listed[encounterID] then order[#order + 1] = encounterID end
                end
                for _, encounterID in ipairs(order) do
                    local er = dr and dr.enc[encounterID]
                    if not (er and er.t == 0) then
                        local encounterName = (encounterID == 0 and L["Loot without encounter"]) or ns.db.enc[encounterID] or (L["Encounter"] .. " " .. encounterID)
                        if encounterID ~= 0 and ns.Lockouts.IsKilled(instanceID, difficultyID, encounterID) then
                            encounterName = ICON_SKULL .. " |cff909090" .. encounterName .. "  " .. L["(dead this week)"] .. "|r"
                        end
                        y = AddRow(y, { text = encounterName, font = "GameFontNormal", counter = er or false, indent = 12 })
                        local seen = {}
                        for _, sourceID in ipairs(d.enc[encounterID]) do
                            if itemRows < MAX_ITEM_ROWS and not seen[sourceID] and ns.Stats.Usable(sourceID, classID) then
                                seen[sourceID] = true
                                if not (missingOnly and ns.Stats.IsCollected(sourceID)) then
                                    y = AddRow(y, ItemRowOptions(sourceID, 28))
                                    itemRows = itemRows + 1
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    if not anyDifficulty then
        y = AddRow(y, { text = "|cff909090" .. L["This instance has no difficulty matching the filter."] .. "|r" })
    end
    if itemRows >= MAX_ITEM_ROWS then
        y = AddRow(y, { text = "|cffff8080" .. L["List truncated: too many items to show."] .. "|r" })
    end
    return y
end

-- Tooltip listing every known character and whether it is saved to this instance difficulty.
function UI.CharactersTooltip(tooltip, instanceID, difficultyID)
    tooltip:AddLine(RowDifficultyName(instanceID, difficultyID), 1, 0.82, 0)
    local list = ns.Lockouts.Characters(instanceID, difficultyID)
    if #list == 0 then
        tooltip:AddLine(L["No character data yet."], 0.7, 0.7, 0.7, true)
        return
    end
    for _, c in ipairs(list) do
        local right = c.free and ("|cff60ff60" .. L["free"] .. "|r") or string.format("|cffffa070%d/%d|r", c.k, c.n)
        tooltip:AddDoubleLine(ns.Lockouts.ColoredName(c.name, c.class), right)
    end
    tooltip:AddLine(L["Characters appear here after logging in with the addon."], 0.6, 0.6, 0.6, true)
end

---------------------------------------------------------------------------
-- Main area: "What should I run?"
---------------------------------------------------------------------------

local function PlaceTodayChecks(y)
    todayRaidsCheck:ClearAllPoints()
    todayRaidsCheck:SetPoint("TOPLEFT", mainContent, "TOPLEFT", 0, -y)
    todayRaidsCheck:SetChecked(S().todayRaids)
    todayRaidsCheck:Show()
    todayDungeonsCheck:ClearAllPoints()
    todayDungeonsCheck:SetPoint("LEFT", todayRaidsCheck, "RIGHT", 90, 0)
    todayDungeonsCheck:SetChecked(S().todayDungeons)
    todayDungeonsCheck:Show()
    return y + 26
end

local function BuildToday(y, stats)
    y = AddHeader(y, L["What should I run?"])
    y = AddRow(y, { text = "|cffa0a0a0" .. L["Where you can still get the most missing pieces this week (bosses already killed do not count). Uses the class and difficulty filters."] .. "|r" })
    y = PlaceTodayChecks(y + 2)
    local ranking = ns.Today.Get(S())
    if not ranking then
        return AddRow(y, { text = L["Calculating…"], font = "GameFontNormal" })
    end
    if #ranking.rows == 0 then
        return AddRow(y, { text = "|cff60ff60" .. L["Nothing left to get this week with the current filters."] .. "|r", font = "GameFontNormal" })
    end
    for i, r in ipairs(ranking.rows) do
        local entry = ns.db.instances[r.instanceID]
        local dr = stats and stats.inst[r.instanceID] and stats.inst[r.instanceID].diffs[r.difficultyID]
        local text = string.format("%d. %s · %s  |cff909090%s|r   |cffffd040%s|r",
            i, entry.name or "?", RowDifficultyName(r.instanceID, r.difficultyID), entry.tierName or "",
            string.format(L["%d to get"], r.available))
        if r.saved then
            text = text .. "  |cffffa070" .. string.format(L["(%d of %d bosses left)"], r.freeBosses, r.bosses) .. "|r"
        end
        y = AddRow(y, {
            text = text,
            font = "GameFontHighlight",
            counter = dr and dr.total or false,
            onClick = function()
                selectedInstance = r.instanceID
                UI.RefreshAll()
                mainScroll:SetVerticalScroll(0)
            end,
            tooltip = function(tooltip)
                tooltip:AddLine(entry.name or "?", 1, 0.82, 0)
                tooltip:AddLine(RowDifficultyName(r.instanceID, r.difficultyID), 1, 1, 1)
                tooltip:AddLine(" ")
                UI.CharactersTooltip(tooltip, r.instanceID, r.difficultyID)
                tooltip:AddLine(L["Click to see what is missing."], 0.6, 0.6, 0.6)
            end,
        })
    end
    if ranking.total > #ranking.rows then
        y = AddRow(y, { text = "|cff909090" .. string.format(L["…and %d more."], ranking.total - #ranking.rows) .. "|r" })
    end
    return y
end

---------------------------------------------------------------------------
-- Main area: search results
---------------------------------------------------------------------------

local function LocationText(sourceID)
    local instanceID, difficultyID, encounterID = ns.Index.Where(sourceID)
    if not instanceID then return "" end
    local entry = ns.db.instances[instanceID]
    local parts = { entry and entry.name or "?", DifficultyName(difficultyID) }
    if encounterID and encounterID ~= 0 and ns.db.enc[encounterID] then parts[#parts + 1] = ns.db.enc[encounterID] end
    return table.concat(parts, " · "), instanceID
end

local function OpenInstance(instanceID)
    return function()
        UI.ClearSearch()
        selectedInstance = instanceID
        UI.RefreshAll()
        mainScroll:SetVerticalScroll(0)
    end
end

local function BuildSearch(y)
    y = AddHeader(y, string.format(L["Search: %s"], searchText))
    local query = (searchText:lower():gsub("^%s+", ""):gsub("%s+$", ""))
    if #query < 2 then
        return AddRow(y, { text = L["Type at least 2 letters."] })
    end
    local result = ns.Index.searchResult
    if not result or ns.Index.searchQuery ~= query or not ns.Index.where then
        return AddRow(y, { text = L["Searching…"], font = "GameFontNormal" })
    end
    local any = false
    if #result.instances > 0 then
        any = true
        y = AddRow(y, { text = L["Instances"], font = "GameFontNormalLarge" })
        local stats = CurrentStats()
        for _, instanceID in ipairs(result.instances) do
            local entry = ns.db.instances[instanceID]
            local ir = stats and stats.inst[instanceID]
            y = AddRow(y, {
                text = (entry.name or "?") .. "  |cff909090" .. (entry.tierName or "") .. "|r",
                font = "GameFontHighlight", indent = 12, counter = ir and ir.total or false,
                onClick = OpenInstance(instanceID),
            })
        end
    end
    if #result.encounters > 0 then
        any = true
        y = AddRow(y, { text = L["Bosses"], font = "GameFontNormalLarge" })
        for _, e in ipairs(result.encounters) do
            local entry = ns.db.instances[e.instanceID]
            y = AddRow(y, {
                text = (ns.db.enc[e.encounterID] or "?") .. "  |cff909090" .. (entry and entry.name or "") .. "|r",
                font = "GameFontHighlight", indent = 12, onClick = OpenInstance(e.instanceID),
            })
        end
    end
    if #result.items > 0 then
        any = true
        y = AddRow(y, { text = L["Pieces"], font = "GameFontNormalLarge" })
        for _, sourceID in ipairs(result.items) do
            local opts = ItemRowOptions(sourceID, 12)
            local where, instanceID = LocationText(sourceID)
            opts.text = opts.text .. "  |cff909090" .. where .. "|r"
            if instanceID then opts.onClick = OpenInstance(instanceID) end
            y = AddRow(y, opts)
        end
        if result.truncated then
            y = AddRow(y, { text = "|cffff8080" .. L["Too many results: type more letters."] .. "|r" })
        end
    end
    if not any then
        y = AddRow(y, { text = "|cff909090" .. L["No results."] .. "|r" })
    end
    return y
end

function UI.ClearSearch()
    if searchText ~= "" then
        searchText = ""
        if searchBox then searchBox:SetText("") end
        ns.Index.Search("", S())
    end
end

-- Re-runs the current search (the class filter and "only missing" change the item results).
function UI.RefreshSearch()
    if searchText == "" then return end
    ns.Index.Search(searchText, S(), function()
        if frame and frame:IsShown() then UI.RefreshMain() end
    end)
end

local searchToken = 0
function UI.SetSearch(text)
    text = text or ""
    if text == searchText then return end
    searchText = text
    if text == "" then
        searchToken = searchToken + 1
        ns.Index.Search("", S())
        UI.RefreshMain()
        return
    end
    searchToken = searchToken + 1
    local token = searchToken
    -- Wait until the player stops typing.
    C_Timer.After(0.35, function()
        if token ~= searchToken then return end
        ns.Index.Ensure(function()
            if token ~= searchToken then return end
            ns.Index.Search(searchText, S(), function()
                if frame and frame:IsShown() then UI.RefreshMain() end
            end)
            UI.RefreshMain()
        end)
        UI.RefreshMain()
    end)
end

function UI.RefreshMain()
    if not frame then return end
    local stats = CurrentStats()
    ResetPool(headerPool); ResetPool(cardPool); ResetPool(rowPool)
    todayRaidsCheck:Hide(); todayDungeonsCheck:Hide()
    local y = 0
    if searchText ~= "" then
        backButton:Hide()
        y = BuildSearch(y)
    elseif selectedInstance then
        backButton:Show()
        backButton:SetText("< " .. TierName(selectedTier or ALL_TIERS))
        y = 30
        y = BuildInstanceDetail(y, selectedInstance, stats)
    else
        backButton:Hide()
        if not next(ns.db.instances) then
            y = AddRow(y, { text = L["No data yet. Press Scan (you can keep playing meanwhile)."], font = "GameFontNormal" })
        elseif selectedTier == TODAY then
            y = BuildToday(y, stats)
        elseif (selectedTier or ALL_TIERS) == ALL_TIERS then
            y = BuildAllTiers(y, stats)
        else
            y = BuildTierOverview(y, selectedTier, stats)
        end
    end
    HideUnused(headerPool); HideUnused(cardPool); HideUnused(rowPool)
    mainContent:SetHeight(math.max(1, y + 10))
end

---------------------------------------------------------------------------
-- Top bar and status line
---------------------------------------------------------------------------

local BLOCK_TEXT = {
    [ns.Runner.BLOCK_COMBAT] = "in combat",
    [ns.Runner.BLOCK_JOURNAL] = "Adventure Guide open",
}

function UI.RefreshStatus()
    if not frame then return end
    local db = ns.db
    local scanning = ns.Scanner.IsRunning()
    scanButton:SetText(scanning and L["Stop"] or L["Scan"])
    classButton:SetText(FilterLabel())
    difficultyButton:SetText(DifficultyLabel())
    missingCheck:SetChecked(S().missingOnly)

    local text
    if scanning then
        local job = ns.Runner:GetJob(ns.Scanner.jobName)
        text = string.format(L["Scanning %d/%s instances"], db.scan.doneInstances or 0, tostring(db.scan.totalInstances or "?"))
        if db.scan.current then text = text .. " · " .. db.scan.current end
        if job and job.blockedReason then
            text = text .. "  |cffffd040" .. string.format(L["paused: %s"], L[BLOCK_TEXT[job.blockedReason] or job.blockedReason]) .. "|r"
        end
    elseif not next(db.instances) then
        text = L["No data yet. Press Scan (you can keep playing meanwhile)."]
    elseif ns.Stats.IsComputing() or (selectedTier == TODAY and ns.Today.IsComputing()) then
        text = L["Calculating percentages…"]
    else
        local stats = CurrentStats()
        text = stats and (L["Total"] .. ": " .. PercentString(stats.total)) or L["Calculating percentages…"]
        if db.scan.needsRefresh then
            text = text .. "  |cffffd040" .. L["(new version: press Scan to update the expansion lists, it is quick)"] .. "|r"
        elseif db.scan.stale then
            text = text .. "  |cffffd040" .. L["(data from another game version: use /tma rescan)"] .. "|r"
        elseif not db.scan.complete then
            text = text .. "  |cffffd040" .. L["(scan incomplete: press Scan to continue)"] .. "|r"
        end
    end
    statusText:SetText(text)
end

function UI.RefreshAll()
    if not frame then return end
    UI.RefreshStatus()
    UI.RefreshNav()
    UI.RefreshMain()
end

function UI.OnStatsReady()
    if frame and frame:IsShown() then UI.RefreshAll() end
end

local lastProgressRefresh = 0
function UI.OnScanProgress()
    if not (frame and frame:IsShown()) then return end
    UI.RefreshStatus()
    if GetTime() - lastProgressRefresh > 3 then
        lastProgressRefresh = GetTime()
        UI.RefreshNav()
        UI.RefreshMain()
    end
end

local function OpenClassMenu(owner)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        local function IsSelected(value) return S().filter == value end
        local function SetSelected(value) S().filter = value; UI.RefreshSearch(); UI.RefreshAll() end
        root:CreateTitle(L["Count pieces for"])
        root:CreateRadio(L["All classes"], IsSelected, SetSelected, "ALL")
        root:CreateRadio(string.format(L["My class (%s)"], ns.Classes.Name(ns.Classes.PlayerClassID())), IsSelected, SetSelected, "MINE")
        root:CreateDivider()
        for _, cls in ipairs(ns.Classes.List()) do
            root:CreateRadio(cls.name, IsSelected, SetSelected, cls.id)
        end
    end)
end

local function OpenDifficultyMenu(owner)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        local function IsSelected(value) return S().difficulty == value end
        local function SetSelected(value) S().difficulty = value; UI.RefreshAll() end
        root:CreateTitle(L["Difficulty"])
        root:CreateRadio(L[DIFFICULTY_LABELS.ALL], IsSelected, SetSelected, "ALL")
        for _, group in ipairs(ns.Stats.DIFFICULTY_GROUPS) do
            root:CreateRadio(L[DIFFICULTY_LABELS[group.key]], IsSelected, SetSelected, group.key)
        end
    end)
end

local function OpenOptionsMenu(owner)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(L["Options"])
        local language = root:CreateButton(L["Language"])
        local function IsLanguage(code) return (S().language or "auto") == code end
        local function SetLanguage(code) UI.SetLanguage(code) end
        language:CreateRadio(L["Automatic (game language)"], IsLanguage, SetLanguage, "auto")
        for _, lang in ipairs(ns.LANGUAGES) do
            language:CreateRadio(lang.name, IsLanguage, SetLanguage, lang.code)
        end
        root:CreateCheckbox(L["Summary when entering an instance"],
            function() return S().overlay end,
            function()
                S().overlay = not S().overlay
                ns.Overlay.QueueUpdate(0.1)
            end)
        root:CreateCheckbox(L["Chat message for new pieces"],
            function() return S().notify end,
            function() S().notify = not S().notify end)
        root:CreateCheckbox(L["Minimap button"],
            function() return not S().minimapHidden end,
            function()
                S().minimapHidden = not S().minimapHidden
                if ns.minimapButton then ns.minimapButton:Refresh() end
            end)
    end)
end

-- Texts that are set once when widgets are created (the rest is redrawn on every refresh).
function UI.ApplyTexts()
    if not frame then return end
    missingCheck.Text:SetText(L["Only missing"])
    todayRaidsCheck.Text:SetText(L["Raids"])
    todayDungeonsCheck.Text:SetText(L["Dungeons"])
    optionsButton:SetText(L["Options"])
    local instructions = searchBox.Instructions -- placeholder text of SearchBoxTemplate
    if type(instructions) == "table" and instructions.SetText then instructions:SetText(L["Search"]) end
end

-- code: "auto", "enUS" or "esES". Applies at once (names from the game keep the client language).
function UI.SetLanguage(code)
    if ns.db then ns.db.settings.language = code end
    ns.SetLanguage(code)
    UI.ApplyTexts()
    UI.RefreshAll()
    if ns.Overlay then ns.Overlay.QueueUpdate(0.1) end
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
    frame = CreateFrame("Frame", "TransmogAtlasFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetClampedToScreen(true)
    frame.TitleText:SetText("TransmogAtlas")
    table.insert(UISpecialFrames, "TransmogAtlasFrame") -- closes with Escape

    classButton = CreateTopButton("", 220, OpenClassMenu)
    classButton:SetPoint("TOPLEFT", 14, -32)
    difficultyButton = CreateTopButton("", 170, OpenDifficultyMenu)
    difficultyButton:SetPoint("LEFT", classButton, "RIGHT", 6, 0)

    missingCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    missingCheck:SetSize(24, 24)
    missingCheck:SetPoint("LEFT", difficultyButton, "RIGHT", 10, 0)
    missingCheck.Text:SetText(L["Only missing"])
    missingCheck:SetScript("OnClick", function(self)
        S().missingOnly = self:GetChecked() and true or false
        UI.RefreshSearch()
        UI.RefreshMain()
    end)

    searchBox = CreateFrame("EditBox", "TransmogAtlasSearchBox", frame, "SearchBoxTemplate")
    searchBox:SetSize(200, 20)
    searchBox:SetPoint("LEFT", missingCheck, "RIGHT", 130, 0)
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(40)
    -- HookScript keeps the template's own behaviour (placeholder text and clear button).
    searchBox:HookScript("OnTextChanged", function(self) UI.SetSearch(self:GetText()) end)
    searchBox:HookScript("OnEscapePressed", function() UI.ClearSearch(); UI.RefreshMain() end)

    scanButton = CreateTopButton(L["Scan"], 110, function()
        if ns.Scanner.IsRunning() then ns.Scanner.Stop() else ns.Scanner.Start() end
        C_Timer.After(0.1, UI.RefreshStatus)
    end)
    scanButton:SetPoint("TOPRIGHT", -14, -32)

    optionsButton = CreateTopButton(L["Options"], 90, OpenOptionsMenu)
    optionsButton:SetPoint("RIGHT", scanButton, "LEFT", -6, 0)

    statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    statusText:SetPoint("TOPLEFT", 16, -62)
    statusText:SetPoint("TOPRIGHT", -16, -62)
    statusText:SetJustifyH("LEFT")

    navScroll, navContent = CreateScroll("TransmogAtlasNavScroll", frame, NAV_W - 20, FRAME_H - 104)
    navScroll:SetPoint("TOPLEFT", 12, -84)

    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetTexture(WHITE)
    divider:SetVertexColor(1, 0.82, 0, 0.2)
    divider:SetWidth(1)
    divider:SetPoint("TOPLEFT", NAV_W + 8, -84)
    divider:SetPoint("BOTTOMLEFT", NAV_W + 8, 14)

    local mainWidth = FRAME_W - NAV_W - 56
    mainScroll, mainContent = CreateScroll("TransmogAtlasMainScroll", frame, mainWidth, FRAME_H - 104)
    mainScroll:SetPoint("TOPLEFT", NAV_W + 18, -84)

    local function TodayCheck(label, field)
        local check = CreateFrame("CheckButton", nil, mainContent, "UICheckButtonTemplate")
        check:SetSize(24, 24)
        check.Text:SetText(label)
        check:SetScript("OnClick", function(self)
            S()[field] = self:GetChecked() and true or false
            UI.RefreshMain()
        end)
        check:Hide()
        return check
    end
    todayRaidsCheck = TodayCheck(L["Raids"], "todayRaids")
    todayDungeonsCheck = TodayCheck(L["Dungeons"], "todayDungeons")

    backButton = CreateFrame("Button", nil, mainContent, "UIPanelButtonTemplate")
    backButton:SetSize(220, 22)
    backButton:SetPoint("TOPLEFT", 0, 0)
    backButton:SetScript("OnClick", function()
        selectedInstance = nil
        UI.RefreshAll()
    end)

    frame:SetScript("OnShow", function()
        ns.Lockouts.Request()
        UI.RefreshAll()
        if ticker then ticker:Cancel() end
        ticker = C_Timer.NewTicker(1, UI.RefreshStatus)
    end)
    frame:SetScript("OnHide", function()
        if ticker then ticker:Cancel(); ticker = nil end
    end)

    UI.ApplyTexts()
end

function UI.Toggle()
    if not frame then
        local ok = ns.SafeCall("build window", Build)
        if not ok then
            ns.Print(L["The window could not be created. See /tma errors."])
            return
        end
        frame:Hide()
    end
    if frame:IsShown() then
        frame:Hide()
        return
    end
    -- Open on the instance the player is in, or on the newest expansion.
    local current = ns.Scanner.CurrentInstanceID()
    if current and ns.db.instances[current] then
        selectedInstance = current
        selectedTier = selectedTier or ns.db.instances[current].tier
    elseif not selectedTier then
        selectedTier = NavTiers()[1] or ALL_TIERS
    end
    frame:Show()
end

function UI.ShowInstance(instanceID)
    if frame then UI.ClearSearch() end
    selectedInstance = instanceID
    if not frame or not frame:IsShown() then UI.Toggle() else UI.RefreshAll() end
end
