-- TransmogAtlas: small summary shown when entering a scanned instance: what is still missing on
-- this difficulty, boss by boss, and which bosses are already dead this week.

local ADDON, ns = ...
local L = ns.L

local Overlay = {}
ns.Overlay = Overlay

local WIDTH = 270
local LINE_H = 15
local MAX_LINES = 16

local frame, title, subtitle, lines
local shownFor -- "instanceID:difficultyID" currently displayed
local dismissedFor -- closed by the player for this instance visit

local function S() return ns.db.settings end

-- Stats for the overlay: the class filter of the main window, every difficulty.
local function StatsSettings()
    return { filter = S().filter, difficulty = "ALL" }
end

local function SavePosition()
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    S().overlayPos = { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function Build()
    frame = CreateFrame("Button", "TransmogAtlasOverlay", UIParent, "TooltipBackdropTemplate")
    frame:SetSize(WIDTH, 60)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        self.draggedAt = GetTime() -- the mouse-up that ends a drag must not count as a click
        SavePosition()
    end)
    local pos = S().overlayPos
    if pos then
        frame:SetPoint(pos.point or "RIGHT", UIParent, pos.relativePoint or "RIGHT", pos.x or -80, pos.y or 120)
    else
        frame:SetPoint("RIGHT", UIParent, "RIGHT", -80, 120)
    end

    title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 10, -9)
    title:SetPoint("RIGHT", -26, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)

    subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
    subtitle:SetPoint("RIGHT", -10, 0)
    subtitle:SetJustifyH("LEFT")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function()
        dismissedFor = shownFor
        frame:Hide()
    end)

    lines = {}
    for i = 1, MAX_LINES do
        local left = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        left:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -6 - (i - 1) * LINE_H)
        left:SetWidth(WIDTH - 80)
        left:SetJustifyH("LEFT")
        left:SetWordWrap(false)
        local right = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        right:SetPoint("TOP", left, "TOP")
        right:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
        right:SetJustifyH("RIGHT")
        lines[i] = { left = left, right = right }
    end

    -- Click (without dragging) opens the full window on this instance.
    frame:RegisterForClicks("LeftButtonUp")
    frame:SetScript("OnClick", function(self)
        if self.draggedAt and GetTime() - self.draggedAt < 0.3 then return end
        if self.instanceID then ns.UI.ShowInstance(self.instanceID) end
    end)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("TransmogAtlas")
        GameTooltip:AddLine(L["Click to open this instance. Drag to move."], 1, 1, 1, true)
        GameTooltip:AddLine(L["/tma overlay turns this window off."], 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame:Hide()
end

local function SetLine(i, left, right)
    lines[i].left:SetText(left or "")
    lines[i].right:SetText(right or "")
    lines[i].left:Show()
    lines[i].right:Show()
end

function Overlay.Update()
    if not ns.db then return end
    local instanceID = ns.Scanner.CurrentInstanceID()
    local entry = instanceID and ns.db.instances[instanceID]
    local difficultyID = select(3, GetInstanceInfo())
    -- Mythic+ (8) drops the Mythic dungeon loot (23) of the Adventure Guide.
    if difficultyID == 8 then difficultyID = 23 end
    local d = entry and difficultyID and entry.diffs and entry.diffs[difficultyID]
    local key = instanceID and (instanceID .. ":" .. tostring(difficultyID))

    if not (S().overlay and d and d.done) then
        if frame then frame:Hide() end
        shownFor, dismissedFor = nil, nil
        return
    end
    if key ~= shownFor then dismissedFor = nil end
    if dismissedFor == key then return end

    if not frame then Build() end
    shownFor = key
    frame.instanceID = instanceID

    local difficultyName = GetDifficultyInfo(difficultyID) or tostring(difficultyID)
    title:SetText((entry.name or "?") .. " · " .. difficultyName)

    local stats = ns.Stats.Get(StatsSettings())
    local used = 0
    if not stats then
        subtitle:SetText(L["Calculating percentages…"])
    else
        local dr = stats.inst[instanceID] and stats.inst[instanceID].diffs[difficultyID]
        local total = dr and dr.total or { t = 0, c = 0 }
        local missing = total.t - total.c
        if total.t == 0 then
            subtitle:SetText(L["Nothing to collect here with the current filters."])
        elseif missing == 0 then
            subtitle:SetText("|cff60ff60" .. string.format(L["Everything collected here (%d/%d)."], total.c, total.t) .. "|r")
        else
            subtitle:SetText(string.format(L["Missing %d of %d pieces (%d%%)"], missing, total.t, math.floor(total.c / total.t * 100)))
            local order = {}
            for _, encounterID in ipairs(entry.encOrder or {}) do order[#order + 1] = encounterID end
            order[#order + 1] = 0
            for _, encounterID in ipairs(order) do
                local er = dr.enc[encounterID]
                local miss = er and (er.t - er.c) or 0
                if miss > 0 and used < MAX_LINES then
                    used = used + 1
                    local name = (encounterID == 0 and L["Loot without encounter"]) or ns.db.enc[encounterID] or tostring(encounterID)
                    if encounterID ~= 0 and ns.Lockouts.IsKilled(instanceID, difficultyID, encounterID) then
                        SetLine(used, "|cff808080" .. name .. "|r", "|cff808080" .. L["dead this week"] .. "|r")
                    else
                        SetLine(used, name, "|cffff7070" .. string.format(L["%d missing"], miss) .. "|r")
                    end
                end
            end
        end
    end
    for i = used + 1, MAX_LINES do
        lines[i].left:Hide()
        lines[i].right:Hide()
    end
    local height = 9 + 14 + 3 + 12 + 10 + (used > 0 and (6 + used * LINE_H) or 0)
    frame:SetHeight(height)
    frame:Show()
end

local pending = false
local function QueueUpdate(delay)
    if pending then return end
    pending = true
    C_Timer.After(delay or 0.5, function()
        pending = false
        ns.SafeCall("overlay update", Overlay.Update)
    end)
end
Overlay.QueueUpdate = QueueUpdate

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:SetScript("OnEvent", function() QueueUpdate(3) end)

-- Refresh when the numbers change, but only while it matters (inside a scanned instance).
local function Refresh()
    if shownFor or (frame and frame:IsShown()) then QueueUpdate(0.5) end
end
ns.On("STATS_READY", Refresh)
ns.On("LOCKOUTS_CHANGED", Refresh)
ns.On("STATS_INVALIDATED", Refresh)
