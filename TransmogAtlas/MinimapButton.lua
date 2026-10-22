-- Minimap button that can be dragged around the minimap. The same file is used by MountAtlas and
-- TransmogAtlas; it only touches the addon's own namespace. The position is saved as an angle.
--
-- ns.CreateMinimapButton(opts):
--   opts.name     global frame name
--   opts.icon     texture path
--   opts.settings table where "minimapAngle" and "minimapHidden" are kept
--   opts.onClick  function(button, mouseButton)
--   opts.onEnter  function(tooltip) to fill the tooltip
--   opts.angle    default position in degrees (0 = right, 90 = top)
-- Returns the button; button:Refresh() applies minimapHidden.

local ADDON, ns = ...

function ns.CreateMinimapButton(opts)
    local settings = opts.settings
    local b = CreateFrame("Button", opts.name, Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("AnyUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local background = b:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    background:SetPoint("TOPLEFT", 7, -5)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetTexture(opts.icon)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetPoint("TOPLEFT", 7, -6)

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    local function Place()
        local angle = math.rad(settings.minimapAngle or opts.angle or 225)
        local radius = Minimap:GetWidth() / 2 + 10
        b:ClearAllPoints()
        b:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
    end

    local function FollowCursor()
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        settings.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
        Place()
    end

    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", FollowCursor)
        GameTooltip:Hide()
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnClick", function(self, mouseButton) opts.onClick(self, mouseButton) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        opts.onEnter(GameTooltip)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    function b:Refresh()
        self:SetShown(not settings.minimapHidden)
        Place()
    end

    b:Refresh()
    return b
end
