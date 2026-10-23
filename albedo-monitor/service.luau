--!nonstrict

local SESSION_RANKS = { working = 1, waiting = 2, unknown = 3, idle = 4 }

local inFlight = false
local snapshot = nil

local function text(value, fallback)
    if type(value) == "string" and value ~= "" then
        return string.sub(value, 1, 512)
    end

    return fallback or ""
end

local function normalizeSession(session)
    return {
        id = text(session.id),
        title = text(session.title, "Untitled session"),
        workspace = text(session.workspace),
        model = text(session.model, "Unknown model"),
        status = SESSION_RANKS[session.status] ~= nil and session.status or "unknown",
        phase = text(session.phase),
        parent_id = text(session.parent_id),
    }
end

local function normalizeWindow(window)
    local remaining = tonumber(window.remaining_percent)

    -- Unknown and non-finite quota values must not become an available balance.
    if remaining ~= nil and remaining == remaining and math.abs(remaining) ~= math.huge then
        remaining = math.clamp(remaining, 0, 100)
    else
        remaining = nil
    end

    local resetsAtEpoch = window.resets_at_epoch
    if
        type(resetsAtEpoch) ~= "number"
        or resetsAtEpoch ~= resetsAtEpoch
        or math.abs(resetsAtEpoch) == math.huge
    then
        resetsAtEpoch = nil
    end

    return {
        label = text(window.label, "Limit"),
        remaining_percent = remaining,
        resets_at = text(window.resets_at),
        resets_at_epoch = resetsAtEpoch,
        observed_at = text(window.observed_at),
        status = text(window.status),
        stale = window.stale ~= false,
    }
end

local function normalizeAccount(account)
    local result = {
        id = text(account.id),
        provider = text(account.provider, "Unknown provider"),
        account = text(account.account, "Default account"),
        error = text(account.error),
        windows = {},
    }

    if type(account.windows) == "table" then
        for _, window in ipairs(account.windows) do
            if type(window) == "table" then
                result.windows[#result.windows + 1] = normalizeWindow(window)
            end
        end
    end

    return result
end

local function normalize(raw)
    if
        type(raw) ~= "table"
        or raw.version ~= 1
        or type(raw.online) ~= "boolean"
        or type(raw.sessions) ~= "table"
        or type(raw.accounts) ~= "table"
    then
        return nil
    end

    local result = {
        version = 1,
        online = raw.online,
        error = text(raw.error),
        accounts_error = text(raw.accounts_error),
        sessions = {},
        accounts = {},
        received_at = os.time(),
        stale = false,
    }

    for _, session in ipairs(raw.sessions) do
        if type(session) == "table" and type(session.id) == "string" then
            result.sessions[#result.sessions + 1] = normalizeSession(session)
        end
    end

    table.sort(result.sessions, function(a, b)
        if SESSION_RANKS[a.status] ~= SESSION_RANKS[b.status] then
            return SESSION_RANKS[a.status] < SESSION_RANKS[b.status]
        end
        if a.title ~= b.title then
            return a.title < b.title
        end
        return a.id < b.id
    end)

    for _, account in ipairs(raw.accounts) do
        if type(account) == "table" then
            result.accounts[#result.accounts + 1] = normalizeAccount(account)
        end
    end

    return result
end

local function failure(message)
    local previous = snapshot or { version = 1, sessions = {}, accounts = {}, accounts_error = "" }

    -- Retain details for inspection, but never present old sessions as live activity.
    snapshot = {
        version = 1,
        online = false,
        stale = true,
        error = message,
        sessions = previous.sessions,
        accounts = previous.accounts,
        accounts_error = previous.accounts_error,
        received_at = previous.received_at,
    }
    noctalia.state.set("snapshot", snapshot)
end

local function receiveSnapshot(result)
    inFlight = false

    if type(result) ~= "table" or result.timedOut == true or result.stdoutTruncated == true then
        failure("Monitor timed out or returned incomplete data")
        return
    end

    local ok, raw = pcall(noctalia.json.decode, result.stdout or "")
    local data = ok and normalize(raw) or nil
    if data == nil then
        failure("Monitor unavailable or returned invalid data")
        return
    end

    snapshot = data
    noctalia.state.set("snapshot", snapshot)
end

local function refresh()
    if inFlight then
        return
    end

    inFlight = true
    local path = text(noctalia.getConfig("monitorPath"), "albedo-monitor")
    path = noctalia.expandPath(path)

    -- The helper owns authentication; argv keeps paths out of a shell.
    -- Let the process deadline expire before Noctalia's native capture timeout.
    local accepted =
        noctalia.runAsync({ "timeout", "12s", path, "--start-daemon" }, receiveSnapshot, 13000)
    if accepted == false then
        inFlight = false
        failure("Monitor could not be started")
    end
end

noctalia.state.watch("command", function(value)
    if type(value) == "table" and value.action == "refresh" then
        refresh()
    end
end)

function update()
    local interval = tonumber(noctalia.getConfig("refreshIntervalSec")) or 60
    noctalia.setUpdateInterval(math.clamp(interval, 2, 300) * 1000)
    refresh()
end

function onIpc(event, _payload)
    if event == "refresh" then
        refresh()
    end
end

update()
