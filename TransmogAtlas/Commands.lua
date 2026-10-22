-- TransmogAtlas: startup and /tma slash commands.

local ADDON, ns = ...
local L = ns.L

ns.version = C_AddOns.GetAddOnMetadata(ADDON, "Version") or "?"

-- Built on demand so it follows the language chosen in the options.
local function Help() return {
    "/tma  - " .. L["open/close the window"],
    "/tma scan [fast]  - " .. L["scan or continue (fast = for when you are AFK)"],
    "/tma stop  - " .. L["stop the scan"],
    "/tma rescan  - " .. L["wipe the data and scan from scratch"],
    "/tma overlay  - " .. L["turn the summary shown when entering an instance on/off"],
    "/tma notify  - " .. L["turn the chat message for new pieces on/off"],
    "/tma lockouts  - " .. L["show this character's saved instances"],
    "/tma probe [id] [diff]  - " .. L["test one instance with detailed logging (no id: the current one)"],
    "/tma verify [id] [diff]  - " .. L["compare the class filter with Blizzard's"],
    "/tma log [n]  - " .. L["show the last n log lines"],
    "/tma errors  - " .. L["show stored errors"],
    "/tma perf  - " .. L["show the addon's performance"],
    "/tma debug  - " .. L["toggle debug messages in chat"],
    "/tma clearlog  - " .. L["clear the log"],
    "/tma lang [auto|en|es]  - " .. L["choose the language: auto, en or es"],
    "/tma minimap  - " .. L["show/hide the minimap button"],
} end

local function ShowLog(n)
    local entries = (TransmogAtlasLog and TransmogAtlasLog.entries) or {}
    n = n or 15
    local first = math.max(1, #entries - n + 1)
    ns.Print(L["Last %d log lines:"], #entries - first + 1)
    for i = first, #entries do print("  " .. entries[i]) end
end

local function ShowErrors()
    local errors = (TransmogAtlasLog and TransmogAtlasLog.errors) or {}
    if #errors == 0 then
        ns.Print(L["No stored errors."])
        return
    end
    for _, e in ipairs(errors) do
        print(string.format("  |cffff6060%s|r x%d (%s): %s", e.where, e.count, e.last, e.msg))
    end
end

local function ShowPerf()
    local snapshot = ns.PerfSnapshot()
    if #snapshot == 0 then
        ns.Print(L["The addon profiler is not available."])
        return
    end
    for _, metric in ipairs(snapshot) do print(string.format("  %s: %.2f", metric.label, metric.value)) end
    ns.LogPerf("command")
end

local COMMANDS = {
    [""] = function() ns.UI.Toggle() end,
    scan = function(args)
        local mode = (args[2] == "fast" or args[2] == "rapido" or args[2] == "rápido") and "fast" or "normal"
        ns.db.settings.scanMode = mode
        ns.Scanner.Start(mode)
    end,
    stop = function() ns.Scanner.Stop() end,
    rescan = function()
        if ns.Scanner.IsRunning() then
            ns.Print(L["Stop the scan first with /tma stop."])
            return
        end
        ns.Scanner.Reset()
        ns.Stats.Invalidate()
        ns.Scanner.Start()
    end,
    overlay = function()
        local s = ns.db.settings
        s.overlay = not s.overlay
        ns.Print(s.overlay and L["Instance summary: on"] or L["Instance summary: off"])
        ns.Overlay.QueueUpdate(0.1)
    end,
    notify = function()
        local s = ns.db.settings
        s.notify = not s.notify
        ns.Print(s.notify and L["New piece messages: on"] or L["New piece messages: off"])
    end,
    lockouts = function()
        local key = ns.Lockouts.CharKey()
        local char = key and ns.db.chars[key]
        local any = false
        for instanceID, diffs in pairs(char and char.saves or {}) do
            for difficultyID in pairs(diffs) do
                local save = ns.Lockouts.Get(instanceID, difficultyID)
                if save then
                    any = true
                    local entry = ns.db.instances[instanceID]
                    print(string.format("  %s · %s: %d/%d", entry and entry.name or instanceID,
                        GetDifficultyInfo(difficultyID) or difficultyID, save.k, save.n))
                end
            end
        end
        if not any then ns.Print(L["No saved instances for this character."]) end
        ns.Lockouts.Request()
    end,
    lang = function(args)
        local codes = { auto = "auto", en = "enUS", es = "esES", enus = "enUS", eses = "esES" }
        local code = codes[(args[2] or ""):lower()]
        if code then ns.UI.SetLanguage(code) end
        ns.Print(L["Language: %s"], ns.language == "esES" and "Español" or "English")
    end,
    minimap = function()
        ns.db.settings.minimapHidden = not ns.db.settings.minimapHidden
        if ns.minimapButton then ns.minimapButton:Refresh() end
    end,
    probe = function(args) ns.Scanner.Probe(tonumber(args[2]), tonumber(args[3])) end,
    verify = function(args) ns.Scanner.Verify(tonumber(args[2]), tonumber(args[3])) end,
    log = function(args) ShowLog(tonumber(args[2])) end,
    errors = ShowErrors,
    perf = ShowPerf,
    debug = function()
        ns.debugMode = not ns.debugMode
        ns.Print(ns.debugMode and L["Debug messages in chat: on"] or L["Debug messages in chat: off"])
    end,
    clearlog = function()
        TransmogAtlasLog = { entries = {}, errors = {} }
        ns.Print(L["Log cleared."])
    end,
}

SLASH_TRANSMOGATLAS1 = "/tma"
SLASH_TRANSMOGATLAS2 = "/transmogatlas"
SlashCmdList.TRANSMOGATLAS = function(msg)
    ns.SafeCall("command /tma " .. tostring(msg), function()
        local args = {}
        for word in (msg or ""):gmatch("%S+") do args[#args + 1] = word end
        local handler = COMMANDS[(args[1] or ""):lower()]
        if handler then
            handler(args)
        else
            for _, line in ipairs(Help()) do print("  " .. line) end
        end
    end)
end

-- Addon compartment (the addons button next to the minimap). Names are referenced from the .toc.
function TransmogAtlas_OnAddonCompartmentClick()
    ns.SafeCall("compartment click", ns.UI.Toggle)
end

local function SummaryTooltip(tooltip)
    tooltip:AddLine("TransmogAtlas")
    tooltip:AddLine(L["Click to open or close the window."], 1, 1, 1)
    local stats = ns.db and ns.Stats.Peek(ns.db.settings)
    if stats and stats.total.t > 0 then
        tooltip:AddLine(string.format("%s: %d%% (%d/%d)", L["Total"], math.floor(stats.total.c / stats.total.t * 100), stats.total.c, stats.total.t), 0.8, 0.8, 0.8)
    end
end

function TransmogAtlas_OnAddonCompartmentEnter(_, button)
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    SummaryTooltip(GameTooltip)
    GameTooltip:Show()
end

function TransmogAtlas_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == ADDON then
        ns.SafeCall("init", ns.InitDB)
        ns.Log("INFO", "Loaded TransmogAtlas %s on build %s (locale %s)", ns.version, select(2, GetBuildInfo()), GetLocale())
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        local db = ns.db
        if db then
            ns.minimapButton = ns.CreateMinimapButton({
                name = "TransmogAtlasMinimapButton",
                icon = "Interface\\Icons\\INV_Chest_Cloth_17",
                settings = db.settings,
                angle = 195,
                onClick = function() ns.SafeCall("minimap click", ns.UI.Toggle) end,
                onEnter = SummaryTooltip,
            })
        end
        if db and db.scan.needsRefresh then
            ns.Print(L["New version: open /tma and press Scan to update the expansion lists (quick)."])
        elseif db and db.scan.totalInstances and not db.scan.complete then
            ns.Print(L["There is an unfinished scan. Use /tma scan to continue it."])
        end
    end
end)
