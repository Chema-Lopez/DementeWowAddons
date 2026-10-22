-- TransmogAtlas: scheduler for long-running jobs, built on coroutines.
--
-- Each job works in short "slices". Inside a job, call ns.Checkpoint() between operations:
-- if the current slice has used up its time budget, the job yields and resumes on a later frame.
--
-- The duty cycle is limited as well: if a slice took X ms, the job rests long enough so that, on
-- average, it only uses a fraction (duty) of the time. An unavoidably heavy call (for example
-- selecting an instance in the Adventure Guide) is therefore spaced out automatically instead of
-- being chained with others.
--
-- IMPORTANT: WoW's Lua cannot coroutine.yield across pcall/xpcall. Jobs are therefore NOT wrapped
-- in xpcall; errors are taken from coroutine.resume's return value and the stack from
-- debugstack(coroutine).

local ADDON, ns = ...

local Runner = {
    jobs = {},
    mode = "normal",
}
ns.Runner = Runner

local PROFILES = {
    normal = { sliceMs = 3, duty = 0.12 }, -- play while it scans
    fast = { sliceMs = 12, duty = 0.6 },   -- leave it running while AFK
}

local SLOW_SLICE_MS = 40 -- slices slower than this are logged as warnings

-- Reasons a job can be paused (the UI translates them).
Runner.BLOCK_COMBAT = "combat"
Runner.BLOCK_JOURNAL = "journal"

local frame = CreateFrame("Frame")
frame:Hide()

local sliceStart = nil

function Runner:SetMode(mode)
    if PROFILES[mode] then
        self.mode = mode
        ns.Log("INFO", "Scheduler mode: %s", mode)
    end
end

local function BlockReason(job)
    if job.pauseInCombat and (InCombatLockdown() or UnitAffectingCombat("player")) then
        return Runner.BLOCK_COMBAT
    end
    if job.needsJournal and EncounterJournal and EncounterJournal:IsShown() then
        return Runner.BLOCK_JOURNAL
    end
    return nil
end

-- opts: needsJournal, pauseInCombat (default true), onDone(result), onStop(reason), onBlock(reason)
function Runner:Start(name, fn, opts)
    if self.jobs[name] then return false end
    opts = opts or {}
    self.jobs[name] = {
        name = name,
        co = coroutine.create(fn),
        wakeAt = 0,
        started = GetTime(),
        slices = 0,
        workMs = 0,
        maxSliceMs = 0,
        needsJournal = opts.needsJournal,
        pauseInCombat = opts.pauseInCombat ~= false,
        onDone = opts.onDone,
        onStop = opts.onStop,
        onBlock = opts.onBlock,
    }
    ns.Log("INFO", "Job started: %s (mode %s)", name, self.mode)
    frame:Show()
    return true
end

-- Stops a job. From outside the job it is removed at once, so a new job with the same name can be
-- started right away; a job stopping itself is removed after its current slice.
function Runner:Stop(name)
    local job = self.jobs[name]
    if not job then return end
    if self.current == job then
        job.stopped = true
        return
    end
    self.jobs[name] = nil
    ns.Log("INFO", "Job %s stopped after %d slices", name, job.slices)
    if job.onStop then ns.SafeCall("onStop " .. name, job.onStop, "stopped") end
end

function Runner:IsRunning(name)
    return self.jobs[name] ~= nil
end

function Runner:GetJob(name)
    return self.jobs[name]
end

-- Call from inside a job between operations.
function ns.Checkpoint()
    if sliceStart and (debugprofilestop() - sliceStart) > PROFILES[Runner.mode].sliceMs then
        coroutine.yield()
    end
end

-- Yields and does not resume until `seconds` have passed.
function ns.Sleep(seconds)
    coroutine.yield(seconds or 0)
end

local function Finish(job, ok, result)
    Runner.jobs[job.name] = nil
    local elapsed = GetTime() - job.started
    if ok then
        ns.Log("INFO", "Job %s finished: %.0f s, %d slices, %.0f ms of work, peak %.1f ms",
            job.name, elapsed, job.slices, job.workMs, job.maxSliceMs)
        if job.onDone then ns.SafeCall("onDone " .. job.name, job.onDone, result) end
    else
        local stack
        local okStack, s = pcall(debugstack, job.co, 0, 20, 10)
        if okStack then stack = s end
        ns.RecordError("job " .. job.name, result, stack)
        if job.onStop then ns.SafeCall("onStop " .. job.name, job.onStop, "error") end
    end
end

frame:SetScript("OnUpdate", function()
    local now = GetTime()
    -- Snapshot the names: callbacks may start or stop jobs while we iterate.
    local names = {}
    for name in pairs(Runner.jobs) do names[#names + 1] = name end
    for _, name in ipairs(names) do
        local job = Runner.jobs[name]
        if not job then
            -- removed by a callback of another job in this same frame
        elseif job.stopped then
            Runner.jobs[name] = nil
            ns.Log("INFO", "Job %s stopped after %d slices", name, job.slices)
            if job.onStop then ns.SafeCall("onStop " .. name, job.onStop, "stopped") end
        else
            local reason = BlockReason(job)
            if reason ~= job.blockedReason then
                job.blockedReason = reason
                if reason then ns.Log("INFO", "Job %s paused: %s", name, reason) end
                if job.onBlock then ns.SafeCall("onBlock " .. name, job.onBlock, reason) end
            end
            if not reason and now >= job.wakeAt then
                sliceStart = debugprofilestop()
                Runner.current = job
                local ok, result = coroutine.resume(job.co)
                Runner.current = nil
                local ms = debugprofilestop() - sliceStart
                sliceStart = nil

                job.slices = job.slices + 1
                job.workMs = job.workMs + ms
                if ms > job.maxSliceMs then job.maxSliceMs = ms end
                if ms > SLOW_SLICE_MS then
                    ns.Log("WARN", "Slow slice in %s: %.1f ms (%s)", name, ms, tostring(job.lastStep or "?"))
                end

                if not ok then
                    Finish(job, false, result)
                elseif coroutine.status(job.co) == "dead" then
                    Finish(job, true, result)
                else
                    local profile = PROFILES[Runner.mode]
                    local rest = (ms / 1000) * (1 / profile.duty - 1)
                    if type(result) == "number" and result > rest then rest = result end
                    job.wakeAt = now + rest
                end
            end
        end
    end
    if not next(Runner.jobs) then frame:Hide() end
end)
