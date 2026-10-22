-- TransmogAtlas: Adventure Guide scanner.
--
-- For every instance and difficulty the loot of the WHOLE instance is read at once (no
-- per-encounter selection, just like the Adventure Guide's own loot tab). For every item with an
-- appearance we store its sourceID, its type and which encounters drop it.
-- The scan is resumable: each finished instance/difficulty is flagged as done.
--
-- An instance can appear in several expansions of the guide (e.g. "Current Season" lists Mythic+
-- dungeons from older expansions). Loot is stored once per instance; expansion membership is kept
-- separately in db.tierInstances.

local ADDON, ns = ...
local L = ns.L

local Scanner = {}
ns.Scanner = Scanner

local SCHEMA = 2
local DUNGEON_DIFFICULTIES = { 1, 2, 23 }                     -- Normal, Heroic, Mythic
local RAID_DIFFICULTIES = { 17, 14, 15, 16, 7, 3, 4, 5, 6, 9 } -- LFR, N, H, M, legacy LFR, 10/25 N/H, 40
local LOOT_WAIT_TRIES = 12   -- retries while waiting for item data to load
local LOOT_WAIT_SECONDS = 0.4

Scanner.jobName = "scan"

local journalTouched = false -- the Adventure Guide was opened while scanning

---------------------------------------------------------------------------
-- Database
---------------------------------------------------------------------------

function ns.InitDB()
    TransmogAtlasDB = TransmogAtlasDB or {}
    local db = TransmogAtlasDB
    db.settings = db.settings or {}
    local s = db.settings
    if s.filter == nil then s.filter = "ALL" end
    s.mode = nil -- removed in 0.3: only exact pieces count
    if s.difficulty == nil then s.difficulty = "ALL" end
    if s.missingOnly == nil then s.missingOnly = true end
    if s.scanMode == nil or s.scanMode == "rapido" then s.scanMode = "normal" end
    if s.overlay == nil then s.overlay = true end        -- 0.4: summary when entering an instance
    if s.notify == nil then s.notify = true end          -- 0.4: chat message when a piece is learned
    if s.todayRaids == nil then s.todayRaids = true end
    if s.todayDungeons == nil then s.todayDungeons = true end
    if s.language == nil then s.language = "auto" end
    ns.SetLanguage(s.language)
    db.chars = db.chars or {}     -- 0.4: lockouts per character (account-wide SavedVariables)
    db.encInfo = db.encInfo or {} -- 0.4: journal encounter -> dungeon encounter ID and map ID
    db.scan = db.scan or {}
    db.instances = db.instances or {}
    db.src = db.src or {}
    db.enc = db.enc or {}
    db.tiers = db.tiers or {}
    db.tierInstances = db.tierInstances or {}

    -- Schema 1 -> 2: expansion membership and instance images did not exist yet.
    -- Loot data is still valid; the next scan only rebuilds the instance lists (fast).
    if (db.schema or 1) < SCHEMA then
        if next(db.instances) then
            db.scan.complete = false
            db.scan.needsRefresh = true
            ns.Log("INFO", "Migrated database from schema %d to %d: a quick scan will refresh expansion lists", db.schema or 1, SCHEMA)
        end
        db.schema = SCHEMA
    end
    ns.db = db

    local build = select(2, GetBuildInfo())
    if db.build and db.build ~= build and next(db.instances) then
        db.scan.stale = true
        ns.Log("INFO", "Data was scanned on build %s and the game is on %s: a rescan is recommended", db.build, build)
    end
    return db
end

function Scanner.Reset()
    local db = ns.db
    wipe(db.instances)
    wipe(db.src)
    wipe(db.enc)
    wipe(db.tiers)
    wipe(db.tierInstances)
    wipe(db.encInfo)
    db.scan = {}
    if ns.Index then ns.Index.Invalidate() end
    ns.Log("INFO", "Scan data wiped")
end

---------------------------------------------------------------------------
-- Adventure Guide state (to leave it as the player had it)
---------------------------------------------------------------------------

local savedJournal

local function EnsureJournal()
    if not C_AddOns.IsAddOnLoaded("Blizzard_EncounterJournal") then
        C_AddOns.LoadAddOn("Blizzard_EncounterJournal")
    end
    return EJ_GetNumTiers ~= nil and C_EncounterJournal ~= nil
end
Scanner.EnsureJournal = EnsureJournal

local function SaveJournalState()
    if savedJournal then return end
    local lootClass, lootSpec = EJ_GetLootFilter()
    savedJournal = {
        tier = EJ_GetCurrentTier(),
        lootClass = lootClass,
        lootSpec = lootSpec,
        slot = C_EncounterJournal.GetSlotFilter(),
    }
end

local function RestoreJournalState()
    if not savedJournal then return end
    local s = savedJournal
    savedJournal = nil
    ns.SafeCall("restore loot filter", EJ_SetLootFilter, s.lootClass or 0, s.lootSpec or 0)
    if s.slot then ns.SafeCall("restore slot filter", C_EncounterJournal.SetSlotFilter, s.slot) end
    if s.tier then ns.SafeCall("restore tier", EJ_SelectTier, s.tier) end
end
Scanner.RestoreJournalState = RestoreJournalState

local function OnBlock(reason)
    if reason == ns.Runner.BLOCK_JOURNAL then journalTouched = true end
end

---------------------------------------------------------------------------
-- Scan steps (run inside a scheduler job)
---------------------------------------------------------------------------

-- Walks every expansion of the guide. Returns the unique instance list (first expansion wins as
-- the instance's "home") and records which instances each expansion lists, in guide order.
local function BuildInstanceList(db)
    local list, seen = {}, {}
    local numTiers = EJ_GetNumTiers() or 0
    for tier = 1, numTiers do
        EJ_SelectTier(tier)
        local tierName = EJ_GetTierInfo(tier)
        db.tiers[tier] = tierName
        local membership = { raids = {}, dungeons = {} }
        for _, isRaid in ipairs({ true, false }) do
            local index = 1
            while true do
                local instanceID, name, _, _, buttonImage = EJ_GetInstanceByIndex(index, isRaid)
                if not instanceID then break end
                table.insert(isRaid and membership.raids or membership.dungeons, instanceID)
                if not seen[instanceID] then
                    seen[instanceID] = true
                    list[#list + 1] = { id = instanceID, name = name, isRaid = isRaid, tier = tier, tierName = tierName, buttonImage = buttonImage }
                end
                index = index + 1
            end
            ns.Checkpoint()
        end
        db.tierInstances[tier] = membership
    end
    return list
end

local function PrepareInstance(db, inst)
    local entry = db.instances[inst.id] or {}
    db.instances[inst.id] = entry
    entry.name, entry.tier, entry.tierName, entry.isRaid = inst.name, inst.tier, inst.tierName, inst.isRaid
    entry.buttonImage = inst.buttonImage
    entry.diffs = entry.diffs or {}
    if entry.diffList then return entry end

    local t0 = debugprofilestop()
    EJ_SelectInstance(inst.id)
    local diffs = {}
    for _, d in ipairs(inst.isRaid and RAID_DIFFICULTIES or DUNGEON_DIFFICULTIES) do
        if EJ_IsValidInstanceDifficulty(d) then diffs[#diffs + 1] = d end
    end
    if #diffs == 0 then
        local current = EJ_GetDifficulty()
        if current then diffs[1] = current end
        ns.Log("DEBUG", "%s (%d): no known difficulty, using the current one (%s)", inst.name, inst.id, tostring(current))
    end

    local encounterOrder = {}
    local j = 1
    while true do
        local encounterName, _, encounterID = EJ_GetEncounterInfoByIndex(j, inst.id)
        if not encounterID then break end
        encounterOrder[#encounterOrder + 1] = encounterID
        db.enc[encounterID] = encounterName
        j = j + 1
    end

    entry.diffList, entry.encOrder = diffs, encounterOrder
    ns.Log("DEBUG", "Prepared %s (%d): %d difficulties, %d encounters, %.1f ms", inst.name, inst.id, #diffs, #encounterOrder, debugprofilestop() - t0)
    return entry
end

local function SelectInstanceDifficulty(instanceID, difficultyID)
    EJ_SelectInstance(instanceID)
    EJ_SetDifficulty(difficultyID)
    EJ_SetLootFilter(0, 0)
    C_EncounterJournal.ResetSlotFilter()
end

-- Counts loot entries that have no link yet (item data not loaded).
local function CountMissing(n)
    local missing = 0
    for i = 1, n do
        local ok, info = pcall(C_EncounterJournal.GetLootInfoByIndex, i)
        if not ok or not info or not info.link then missing = missing + 1 end
        ns.Checkpoint()
    end
    return missing
end

-- Processes loot entry i of the current selection. Returns true if it has an appearance.
-- It never yields, so it can safely run inside xpcall.
local function ProcessLootEntry(db, d, i)
    local info = C_EncounterJournal.GetLootInfoByIndex(i)
    if not (info and info.itemID) then return false end
    local appearanceID, sourceID = C_TransmogCollection.GetItemInfo(info.link or info.itemID)
    if not sourceID then return false end
    if not db.src[sourceID] then
        local _, _, _, equipLoc, _, classID, subClassID = C_Item.GetItemInfoInstant(info.itemID)
        -- The set class mask (m) is filled lazily by Classes.CanUseSource once set data is loaded.
        db.src[sourceID] = { i = info.itemID, a = appearanceID, c = classID, s = subClassID, e = equipLoc }
    end
    local numEncounters = EJ_GetNumEncountersForLootByIndex(i) or 1
    if numEncounters < 1 then numEncounters = 1 end
    for k = 1, numEncounters do
        local encounterInfo = (k == 1) and info or C_EncounterJournal.GetLootInfoByIndex(i, k)
        local encounterID = (encounterInfo and encounterInfo.encounterID) or 0
        local list = d.enc[encounterID]
        if not list then list = {}; d.enc[encounterID] = list end
        list[#list + 1] = sourceID
    end
    return true
end

-- Returns "ok", "retry" (must repeat because the guide was touched) or "empty".
local function ScanDifficulty(db, instanceID, entry, difficultyID, verbose)
    local job = ns.Runner:GetJob(Scanner.jobName)
    local t0 = debugprofilestop()
    SelectInstanceDifficulty(instanceID, difficultyID)
    local selectMs = debugprofilestop() - t0
    if job then job.lastStep = string.format("%s diff %d", entry.name or instanceID, difficultyID) end

    -- Wait for the game to load the item data.
    local n = EJ_GetNumLoot() or 0
    local missing = CountMissing(n)
    local tries = 0
    while missing > 0 and tries < LOOT_WAIT_TRIES do
        tries = tries + 1
        ns.Sleep(LOOT_WAIT_SECONDS)
        if journalTouched then journalTouched = false; return "retry" end
        n = EJ_GetNumLoot() or 0
        missing = CountMissing(n)
    end
    if journalTouched then journalTouched = false; return "retry" end

    local d = { enc = {}, n = n, missing = missing, waits = tries }
    local added, failed = 0, 0
    for i = 1, n do
        -- Each item is processed protected: if one fails it is recorded and the scan goes on.
        local ok, res = xpcall(ProcessLootEntry, ns.ErrorHandler, db, d, i)
        if ok then
            if res then added = added + 1 end
        else
            failed = failed + 1
            ns.RecordError(string.format("item %d of %s diff %d", i, entry.name or tostring(instanceID), difficultyID),
                type(res) == "table" and res.msg or res, type(res) == "table" and res.stack or nil)
        end
        ns.Checkpoint()
        if journalTouched then journalTouched = false; return "retry" end
    end
    d.failed = failed
    d.done = true
    entry.diffs[difficultyID] = d

    local level = (missing > 0 or failed > 0) and "WARN" or (verbose and "INFO" or "DEBUG")
    ns.Log(level, "%s diff %d: %d items, %d with appearance, %d not loaded after %d waits, %d failed, select %.1f ms",
        entry.name or tostring(instanceID), difficultyID, n, added, missing, tries, failed, selectMs)
    return n > 0 and "ok" or "empty"
end

---------------------------------------------------------------------------
-- Public jobs
---------------------------------------------------------------------------

local function ScanJob()
    local db = ns.db
    SaveJournalState()
    ns.LogPerf("scan start")
    db.scan.complete = false
    db.scan.startedAt = db.scan.startedAt or time()

    local list = BuildInstanceList(db)
    db.scan.totalInstances = #list
    db.scan.doneInstances = 0

    for index, inst in ipairs(list) do
        local entry = PrepareInstance(db, inst)
        ns.Checkpoint()
        for _, difficultyID in ipairs(entry.diffList) do
            local existing = entry.diffs[difficultyID]
            if not (existing and existing.done) then
                local result = ScanDifficulty(db, inst.id, entry, difficultyID)
                local retries = 0
                while result == "retry" and retries < 3 do
                    retries = retries + 1
                    ns.Log("INFO", "Repeating %s diff %d (the Adventure Guide was opened)", entry.name, difficultyID)
                    result = ScanDifficulty(db, inst.id, entry, difficultyID)
                end
                ns.Checkpoint()
            end
        end
        db.scan.doneInstances = index
        db.scan.current = inst.name
        if ns.UI and ns.UI.OnScanProgress then ns.UI.OnScanProgress() end
    end

    db.scan.complete = true
    db.scan.stale = nil
    db.scan.needsRefresh = nil
    db.scan.current = nil
    db.scan.finishedAt = time()
    db.build = select(2, GetBuildInfo())
    RestoreJournalState()
    ns.LogPerf("scan end")
    return #list
end

function Scanner.Start(mode)
    if ns.Runner:IsRunning(Scanner.jobName) then
        ns.Print(L["A scan is already running."])
        return
    end
    if ns.Runner:IsRunning("verify") or ns.Runner:IsRunning("probe") then
        ns.Print(L["Wait for the current test to finish."])
        return
    end
    if not EnsureJournal() then
        ns.Print(L["Could not load the Adventure Guide."])
        return
    end
    ns.Runner:SetMode(mode or ns.db.settings.scanMode or "normal")
    ns.Runner:Start(Scanner.jobName, ScanJob, {
        needsJournal = true,
        onBlock = OnBlock,
        onDone = function(count)
            ns.Print(L["Scan finished: %d instances."], count or 0)
            if ns.Index then ns.Index.Invalidate() end
            if ns.Stats then ns.Stats.Invalidate() end
            if ns.UI and ns.UI.OnScanProgress then ns.UI.OnScanProgress() end
        end,
        onStop = function(reason)
            RestoreJournalState()
            if reason ~= "stopped" then ns.Print(L["The scan stopped because of an error. Use /tma errors to see it."]) end
            if ns.UI and ns.UI.OnScanProgress then ns.UI.OnScanProgress() end
        end,
    })
    ns.Print(L["Scanning in the background (%s mode). It pauses in combat or while the Adventure Guide is open."],
        ns.Runner.mode == "fast" and L["fast"] or L["normal"])
end

function Scanner.Stop()
    ns.Runner:Stop(Scanner.jobName)
end

function Scanner.IsRunning()
    return ns.Runner:IsRunning(Scanner.jobName)
end

---------------------------------------------------------------------------
-- World bosses
---------------------------------------------------------------------------

-- Every expansion has an Adventure Guide "instance" that groups its outdoor world bosses (e.g.
-- "Pandaria", "Draenor", "Khaz Algar"). Its loot is real, but it is not something you "run".
local WORLD_BOSS_INSTANCES = {
    [322] = true,  -- Pandaria
    [557] = true,  -- Draenor
    [822] = true,  -- Broken Isles
    [959] = true,  -- Invasion Points (Argus)
    [1028] = true, -- Azeroth (Battle for Azeroth)
    [1192] = true, -- Shadowlands
    [1205] = true, -- Dragon Isles
    [1278] = true, -- Khaz Algar
    [1312] = true, -- Midnight
}

-- Known IDs first; for future expansions, the guide hides the difficulty selector for world
-- bosses and their map is not a dungeon map. The answer is cached in the instance entry.
function Scanner.IsWorldBosses(instanceID)
    if WORLD_BOSS_INSTANCES[instanceID] then return true end
    local entry = ns.db.instances[instanceID]
    if not entry then return false end
    if entry.world == nil then
        entry.world = false
        if EJ_GetInstanceInfo then
            local ok, _, _, _, _, _, _, dungeonAreaMapID, _, shouldDisplayDifficulty = pcall(EJ_GetInstanceInfo, instanceID)
            if ok and shouldDisplayDifficulty == false then
                local info = dungeonAreaMapID and dungeonAreaMapID > 0 and C_Map.GetMapInfo(dungeonAreaMapID)
                -- Enum.UIMapType: 0 cosmic, 1 world, 2 continent, 3 zone, 4 dungeon, 5 micro, 6 orphan
                if not info or (info.mapType and info.mapType <= 3) then
                    entry.world = true
                    ns.Log("INFO", "%s (%d) detected as world bosses", entry.name or "?", instanceID)
                end
            end
        end
    end
    return entry.world
end

---------------------------------------------------------------------------
-- Diagnostics
---------------------------------------------------------------------------

-- Adventure Guide instance for the zone the player is in.
function Scanner.CurrentInstanceID()
    -- 8th return of GetInstanceInfo() is the game map ID of the instance.
    local instanceMapID = select(8, GetInstanceInfo())
    if instanceMapID and C_EncounterJournal and C_EncounterJournal.GetInstanceForGameMap then
        local id = C_EncounterJournal.GetInstanceForGameMap(instanceMapID)
        if id and id > 0 then return id end
    end
    return nil
end

local function FindInstance(db, instanceID)
    for _, inst in ipairs(BuildInstanceList(db)) do
        if inst.id == instanceID then return inst end
    end
end

-- /tma probe: scans a single instance with detailed logging.
function Scanner.Probe(instanceID, difficultyID)
    if Scanner.IsRunning() or ns.Runner:IsRunning("verify") then
        ns.Print(L["Wait for the current scan or test to finish."])
        return
    end
    if not EnsureJournal() then return end
    instanceID = instanceID or Scanner.CurrentInstanceID()
    if not instanceID then
        ns.Print(L["Usage: /tma probe <instanceID> [difficulty] (or use it inside an instance)"])
        return
    end
    ns.Runner:Start("probe", function()
        local db = ns.db
        SaveJournalState()
        local inst = FindInstance(db, instanceID)
        if not inst then
            ns.Log("WARN", "probe: instance %d is not in the Adventure Guide", instanceID)
            RestoreJournalState()
            return
        end
        local entry = PrepareInstance(db, inst)
        local diffs = difficultyID and { difficultyID } or entry.diffList
        ns.Log("INFO", "probe %s (%d): difficulties %s, encounters %d", inst.name, inst.id, table.concat(entry.diffList, ","), #entry.encOrder)
        for _, d in ipairs(diffs) do
            ScanDifficulty(db, inst.id, entry, d, true)
        end
        RestoreJournalState()
        ns.LogPerf("probe")
    end, {
        needsJournal = true,
        onBlock = OnBlock,
        onDone = function() ns.Print(L["Test finished. Details in /tma log."]) end,
        onStop = RestoreJournalState,
    })
end

-- /tma verify: compares our class table against Blizzard's class loot filter.
function Scanner.Verify(instanceID, difficultyID)
    if Scanner.IsRunning() or ns.Runner:IsRunning("probe") then
        ns.Print(L["Wait for the current scan or test to finish."])
        return
    end
    if not EnsureJournal() then return end
    instanceID = instanceID or Scanner.CurrentInstanceID()
    if not instanceID then
        ns.Print(L["Usage: /tma verify <instanceID> [difficulty] (or use it inside an instance)"])
        return
    end
    ns.Runner:Start("verify", function()
        local db = ns.db
        SaveJournalState()
        local inst = FindInstance(db, instanceID)
        if not inst then RestoreJournalState(); return end
        local entry = PrepareInstance(db, inst)
        local d = difficultyID or entry.diffList[#entry.diffList]
        SelectInstanceDifficulty(inst.id, d)
        ns.Sleep(1)

        -- Full list (all classes)
        local all = {}
        for i = 1, EJ_GetNumLoot() or 0 do
            local info = C_EncounterJournal.GetLootInfoByIndex(i)
            if info and info.itemID then
                local _, sourceID = C_TransmogCollection.GetItemInfo(info.link or info.itemID)
                if sourceID then
                    local _, _, _, equipLoc, _, classID, subClassID = C_Item.GetItemInfoInstant(info.itemID)
                    all[info.itemID] = { c = classID, s = subClassID, e = equipLoc, m = ns.Classes.SetClassMask(sourceID) }
                end
            end
        end

        local weExclude, weInclude = 0, 0
        for _, cls in ipairs(ns.Classes.List()) do
            EJ_SetLootFilter(cls.id, 0)
            ns.Sleep(0.5)
            local blizzard = {}
            for i = 1, EJ_GetNumLoot() or 0 do
                local info = C_EncounterJournal.GetLootInfoByIndex(i)
                if info and info.itemID then blizzard[info.itemID] = true end
            end
            for itemID, meta in pairs(all) do
                local ours = ns.Classes.CanUse(meta, cls.id)
                if blizzard[itemID] and not ours then
                    weExclude = weExclude + 1
                    ns.Log("WARN", "verify %s: Blizzard YES / ours NO -> item %d (%s, class %s/%s, set mask %s)", cls.file, itemID, tostring(meta.e), tostring(meta.c), tostring(meta.s), tostring(meta.m))
                elseif ours and not blizzard[itemID] then
                    weInclude = weInclude + 1
                    ns.Log("DEBUG", "verify %s: ours YES / Blizzard NO -> item %d (%s, %s/%s)", cls.file, itemID, tostring(meta.e), tostring(meta.c), tostring(meta.s))
                end
            end
            ns.Checkpoint()
        end
        ns.Log("INFO", "verify %s diff %d: %d items we exclude but Blizzard shows (check these), %d we include but Blizzard filters (expected: Blizzard also filters by stats)",
            inst.name, d, weExclude, weInclude)
        RestoreJournalState()
    end, {
        needsJournal = true,
        onDone = function() ns.Print(L["Verification finished. Results in /tma log."]) end,
        onStop = RestoreJournalState,
    })
end
