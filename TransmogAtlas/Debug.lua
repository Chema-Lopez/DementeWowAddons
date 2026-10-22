-- TransmogAtlas: persistent log, error capture and performance metrics.
-- Everything recorded here ends up in WTF/.../SavedVariables/TransmogAtlas.lua (TransmogAtlasLog)
-- after a /reload or logout, so it can be inspected outside the game.
-- Log lines are developer-facing and intentionally kept in English.

local ADDON, ns = ...

local MAX_LOG = 600
local MAX_ERRORS = 50
local PREFIX = "|cffc080ff[TMA]|r "

ns.debugMode = false

local function LogTable()
    TransmogAtlasLog = TransmogAtlasLog or {}
    local log = TransmogAtlasLog
    log.entries = log.entries or {}
    log.errors = log.errors or {}
    return log
end

-- User-facing chat message. `fmt` should already be localized (ns.L).
function ns.Print(fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    print(PREFIX .. (ok and msg or tostring(fmt)))
end

-- level: "INFO", "WARN", "ERROR", "DEBUG"
function ns.Log(level, fmt, ...)
    local ok, msg = pcall(string.format, fmt, ...)
    if not ok then msg = tostring(fmt) end
    local log = LogTable()
    log.entries[#log.entries + 1] = date("%m-%d %H:%M:%S") .. " [" .. level .. "] " .. msg
    while #log.entries > MAX_LOG do table.remove(log.entries, 1) end
    if level == "ERROR" or (ns.debugMode and level ~= "DEBUG") then
        print(PREFIX .. msg)
    end
end

-- Stores an error with its stack trace. Repeated errors increase a counter instead of duplicating.
function ns.RecordError(where, err, stack)
    local log = LogTable()
    local key = where .. " | " .. tostring(err)
    for _, e in ipairs(log.errors) do
        if e.key == key then
            e.count = e.count + 1
            e.last = date("%m-%d %H:%M:%S")
            return
        end
    end
    log.errors[#log.errors + 1] = {
        key = key,
        where = where,
        msg = tostring(err),
        stack = stack,
        count = 1,
        first = date("%m-%d %H:%M:%S"),
        last = date("%m-%d %H:%M:%S"),
        version = ns.version,
        build = select(2, GetBuildInfo()),
    }
    while #log.errors > MAX_ERRORS do table.remove(log.errors, 1) end
    ns.Log("ERROR", "%s: %s", where, tostring(err))
end

-- xpcall handler: returns the error together with the stack at the point of failure.
function ns.ErrorHandler(err)
    return { msg = err, stack = debugstack(2, 20, 10) }
end

-- Runs fn protected. Do NOT use with functions that call coroutine.yield:
-- WoW's Lua cannot yield across pcall/xpcall.
function ns.SafeCall(where, fn, ...)
    local ok, res = xpcall(fn, ns.ErrorHandler, ...)
    if not ok then
        if type(res) == "table" then
            ns.RecordError(where, res.msg, res.stack)
        else
            ns.RecordError(where, res)
        end
        return false
    end
    return true, res
end

-- Tiny internal event bus so modules do not need to know about each other.
-- Events: "STATS_READY", "STATS_INVALIDATED", "LOCKOUTS_CHANGED", "INDEX_READY".
-- Listeners run protected and must not yield.
local listeners = {}

function ns.On(event, fn)
    listeners[event] = listeners[event] or {}
    table.insert(listeners[event], fn)
end

function ns.Fire(event, ...)
    for _, fn in ipairs(listeners[event] or {}) do
        ns.SafeCall("callback " .. event, fn, ...)
    end
end

-- Metrics from the game's own addon profiler (C_AddOnProfiler).
local METRICS = {
    { "PeakTime", "Peak (ms)" },
    { "RecentAverageTime", "Recent average (ms)" },
    { "CountTimeOver10Ms", "Frames > 10 ms" },
    { "CountTimeOver50Ms", "Frames > 50 ms" },
    { "CountTimeOver100Ms", "Frames > 100 ms" },
}

function ns.PerfSnapshot()
    local out = {}
    if not (C_AddOnProfiler and C_AddOnProfiler.GetAddOnMetric and Enum.AddOnProfilerMetric) then
        return out
    end
    for _, metric in ipairs(METRICS) do
        local enumValue = Enum.AddOnProfilerMetric[metric[1]]
        if enumValue then
            local ok, value = pcall(C_AddOnProfiler.GetAddOnMetric, ADDON, enumValue)
            if ok and value then out[#out + 1] = { label = metric[2], key = metric[1], value = value } end
        end
    end
    return out
end

function ns.LogPerf(context)
    local parts = {}
    for _, metric in ipairs(ns.PerfSnapshot()) do
        parts[#parts + 1] = string.format("%s=%.1f", metric.key, metric.value)
    end
    ns.Log("INFO", "Performance (%s): %s", context or "-", #parts > 0 and table.concat(parts, " ") or "profiler not available")
end
