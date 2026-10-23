--!nonstrict

-- State watchers connect the real entry scripts without starting Noctalia.
local state, watchers = {}, {}
local pending, command, lastBar, lastPanel, lastTooltip, selectedPanel
local started, panelRenders = 0, 0
local accepted = true
local settingReads, cornerScale = 0, 0
local config = { monitorPath = "/tmp/space ' ; $/albedo-monitor" }
local interval
local noctalia = {
    getConfig = function(key)
        return config[key]
    end,
    getSetting = function(key)
        assert(key == "shell.corner_radius_scale")
        settingReads = settingReads + 1
        return cornerScale
    end,
    expandPath = function(value)
        return value
    end,
    setUpdateInterval = function(value)
        interval = value
    end,
    state = {
        get = function(key)
            return state[key]
        end,
        set = function(key, value)
            state[key] = value
            for _, callback in ipairs(watchers[key] or {}) do
                callback(value)
            end
        end,
        watch = function(key, callback)
            watchers[key] = watchers[key] or {}
            table.insert(watchers[key], callback)
        end,
    },
    runAsync = function(argv, callback, timeout)
        assert(timeout == 13000, "Native timeout must exceed the helper deadline")
        command = argv
        started = started + 1
        if accepted then
            pending = callback
        end
        return accepted
    end,
    json = {
        decode = function(value)
            if type(value) ~= "table" then
                error("invalid JSON")
            end
            return value
        end,
    },
    togglePanel = function(id)
        selectedPanel = id
    end,
}
local ui = setmetatable({}, {
    __index = function(_, kind)
        return function(props, children)
            return { kind = kind, props = props, children = children }
        end
    end,
})
local barWidget = {
    render = function(tree)
        lastBar = tree
    end,
    setTooltip = function(value)
        lastTooltip = value
    end,
}
local panel = {
    render = function(tree)
        lastPanel = tree
        panelRenders = panelRenders + 1
    end,
    close = function() end,
}

do
    -- SERVICE_SOURCE
end
-- Entry callbacks are global, so preserve the service callback before loading the UI.
local serviceUpdate = update

do
    -- STATUS_SOURCE
end
local statusClick, statusRefresh = onClick, onRightClick

do
    -- PANEL_SOURCE
end

local function texts(tree)
    local out = {}
    local function visit(node)
        if type(node) ~= "table" then
            return
        end
        if node.props and node.props.text then
            table.insert(out, node.props.text)
        end
        for _, child in ipairs(node.children or {}) do
            visit(child)
        end
    end
    visit(tree)
    return table.concat(out, "\n")
end
local function contains(tree, expected)
    assert(
        string.find(texts(tree), expected, 1, true) ~= nil,
        "Missing " .. expected .. " in " .. texts(tree)
    )
end
local function reply(data, code)
    local callback = pending
    pending = nil
    assert(callback ~= nil, "No request to complete")
    callback({ exitCode = code or 0, stdout = data })
end
local function request()
    serviceUpdate()
    assert(pending ~= nil)
end
local function sample()
    return {
        version = 1,
        online = true,
        error = "",
        accounts_error = "",
        sessions = {
            { id = "idle", title = "Idle", status = "idle" },
            { id = "wait", title = "Approval", status = "waiting", phase = "idle" },
            {
                id = "child",
                title = "Child",
                status = "working",
                parent_id = "parent",
                model = "gpt-test",
                workspace = "/test",
            },
            { id = "parent", title = "Parent", status = "working" },
        },
        accounts = {
            {
                provider = "codex",
                account = "one",
                error = "",
                windows = {
                    {
                        label = "Session",
                        remaining_percent = 63,
                        resets_at = "2026-10-17T12:00:00Z",
                        observed_at = "2026-10-17T10:00:00Z",
                        stale = false,
                    },
                    { label = "Weekly", remaining_percent = 0, stale = true },
                },
            },
            { provider = "claude", account = "two", error = "quota_unavailable", windows = {} },
        },
    }
end

assert(started == 1 and interval == 60000, "Default refresh must be one minute")
assert(type(command) == "table" and command[1] == "timeout" and command[2] == "12s")
assert(command[3] == config.monitorPath and #command == 3, "Path must stay one literal argument")
serviceUpdate()
assert(started == 1, "Requests must not overlap")
contains(lastBar, "offline")
reply(sample())
assert(state.snapshot.sessions[1].status == "working")
contains(lastBar, "2 active")
contains(lastBar, "1 waiting")
contains(lastBar, "63% left")
contains(lastBar, "codex · one")
contains(lastBar, "claude · two")
contains(lastBar, "Weekly Stale")
contains(lastBar, "Quota unavailable")
assert(not string.find(texts(lastBar), "0% left", 1, true), "Stale quota cannot look current")
assert(panelRenders == 0, "Closed panels must not render")
statusClick()
assert(selectedPanel == "adam0/albedo-monitor:panel")
onOpen({})
contains(lastPanel, "DAEMON ONLINE")
contains(lastPanel, "↳ Child")
contains(lastPanel, "quota_unavailable")
contains(lastPanel, "Quota unavailable")
contains(lastPanel, "0% left · stale")
contains(lastPanel, "Resets 2026-10-17T12:00:00Z")
contains(lastPanel, "Observed 2026-10-17T10:00:00Z")
assert(pending ~= nil, "Opening panel requests fresh snapshot")
reply("invalid JSON", 1)
assert(state.snapshot.stale and not state.snapshot.online)
assert(#state.snapshot.sessions == 4, "Keep last data only as explicitly stale")
contains(lastBar, "offline")
assert(
    not string.find(texts(lastBar), "2 active", 1, true),
    "Stale sessions must not appear active"
)
contains(lastPanel, "showing last known data")
contains(lastPanel, "last known: working")

request()
reply({ version = 2, online = true, sessions = {}, accounts = {} })
assert(state.snapshot.stale, "Unknown schema is invalid")
request()
local truncated = pending
pending = nil
truncated({ stdoutTruncated = true, exitCode = 0, stdout = sample() })
assert(state.snapshot.stale)
request()
local timedOut = pending
pending = nil
timedOut({ timedOut = true, exitCode = 124, stdout = sample() })
assert(state.snapshot.stale)
request()
reply({ version = 1, online = false, error = "daemon_offline", sessions = {}, accounts = {} }, 1)
assert(not state.snapshot.online and not state.snapshot.stale and #state.snapshot.sessions == 0)
contains(lastPanel, "daemon_offline")
accepted = false
serviceUpdate()
assert(state.snapshot.error == "Monitor could not be started")
accepted = true
request()
reply(sample())
contains(lastBar, "2 active")
assert(state.snapshot.error == "" and not state.snapshot.stale)

local partial = sample()
partial.error = "sessions_truncated"
partial.sessions = {}
request()
reply(partial)
contains(lastBar, "status unavailable")
contains(lastBar, "Session 63% left")
contains(lastPanel, "PARTIAL SNAPSHOT")
contains(lastPanel, "Session status unavailable")
assert(not string.find(texts(lastPanel), "No open sessions", 1, true))
assert(not string.find(texts(lastBar), "2 active", 1, true))

local malformed = sample()
malformed.sessions = { false, {}, { id = "strange", status = "flying" } }
malformed.accounts[1].windows = {
    { remaining_percent = 120 },
    { remaining_percent = -10 },
    { remaining_percent = "invalid" },
    { remaining_percent = 0 / 0 },
    { remaining_percent = math.huge },
}
request()
reply(malformed)
assert(#state.snapshot.sessions == 1 and state.snapshot.sessions[1].status == "unknown")
local windows = state.snapshot.accounts[1].windows
assert(windows[1].remaining_percent == 100 and windows[2].remaining_percent == 0)
assert(
    windows[3].remaining_percent == nil
        and windows[4].remaining_percent == nil
        and windows[5].remaining_percent == nil
)
contains(lastPanel, "Unknown")

local large = sample()
large.sessions = {}
for i = 1, 100 do
    table.insert(large.sessions, { id = tostring(i), title = "Session " .. i, status = "working" })
end
request()
reply(large)
contains(lastBar, "100 active")
contains(lastPanel, "40 more sessions")
onClose()
local renders = panelRenders
request()
reply(sample())
assert(panelRenders == renders, "Closed panel received update")
statusRefresh()
assert(pending ~= nil)
reply({ version = 1, online = true, sessions = {}, accounts = {} })
contains(lastBar, "0 active")
assert(not string.find(texts(lastBar), "% left", 1, true))
config.refreshIntervalSec = 0
serviceUpdate()
assert(interval == 2000)
reply(sample())
onOpen({})
reply(sample())
local function checkProgressRadius(tree, radius, expectedCount)
    local count = 0
    local function visit(node)
        if type(node) ~= "table" then
            return
        end
        if node.kind == "progress" then
            assert(node.props.radius == radius, "Theme radius changed")
            count = count + 1
        end
        for _, child in ipairs(node.children or {}) do
            visit(child)
        end
    end
    visit(tree)
    assert(count == expectedCount, "Unexpected quota meter count")
end
for _, case in ipairs({
    { value = 0, radius = 0 },
    { value = 1.5, radius = 3 },
    { value = "invalid", radius = 2 },
    { radius = 2 },
}) do
    cornerScale = case.value
    settingReads = 0
    noctalia.state.set("snapshot", state.snapshot)
    assert(settingReads == 2, "Read theme scale once each for bar and open panel")
    checkProgressRadius(lastPanel, case.radius, 2)
    checkProgressRadius(lastBar, case.radius, 1)
end

local function collectNodes(tree, kind)
    local result = {}
    local function visit(node)
        if type(node) ~= "table" then
            return
        end
        if node.kind == kind then
            result[#result + 1] = node
        end
        for _, child in ipairs(node.children or {}) do
            visit(child)
        end
    end
    visit(tree)
    return result
end

local function tooltipText()
    local lines = {}
    for _, entry in ipairs(lastTooltip) do
        lines[#lines + 1] = entry.key .. ": " .. entry.value
    end
    return table.concat(lines, "\n")
end

local function tooltipContains(expected)
    assert(string.find(tooltipText(), expected, 1, true), "Missing tooltip detail " .. expected)
end

-- More than CodexBar's provider cap: every account and every fresh window stays visible.
local inventory = sample()
inventory.accounts = {}
for index = 1, 6 do
    inventory.accounts[#inventory.accounts + 1] = {
        id = "public-" .. tostring(index),
        provider = "codex",
        account = "Account " .. tostring(index),
        windows = {
            {
                label = "Session",
                remaining_percent = index * 10,
                stale = false,
                status = "ok",
                resets_at = "2026-10-17T12:00:00Z",
                observed_at = "2026-10-17T10:00:00Z",
            },
            { label = "Weekly", remaining_percent = 100 - index, stale = false },
        },
    }
end
request()
reply(inventory)
for index = 1, 6 do
    contains(lastBar, "codex · Account " .. tostring(index))
    contains(lastBar, tostring(index * 10) .. "% left")
    contains(lastBar, tostring(100 - index) .. "% left")
    tooltipContains("public-" .. tostring(index))
end
local meters = collectNodes(lastBar, "progress")
assert(#meters == 12, "Render all windows, not just a global or per-provider minimum")
assert(meters[1].props.progress == 0.1 and meters[1].props.fill == "error")
assert(meters[3].props.progress == 0.2 and meters[3].props.fill == "tertiary")
assert(meters[7].props.progress == 0.4 and meters[7].props.fill == "primary")
assert(meters[1].props.width == 26 and meters[1].props.height == 4)
tooltipContains("Resets 2026-10-17T12:00:00Z")
tooltipContains("Observed 2026-10-17T10:00:00Z")
tooltipContains("Snapshot:")

local uncertain = sample()
uncertain.accounts[1].windows = {
    { label = "Empty", remaining_percent = 0, stale = false },
    { label = "Full", remaining_percent = 100, stale = false },
    { label = "Missing", stale = false },
    { label = "Old", remaining_percent = 42, stale = true },
    { label = "No freshness", remaining_percent = 55 },
    { label = "Broken", remaining_percent = 56, stale = false, status = "provider_error" },
}
uncertain.accounts[2].windows = {
    { label = "Rejected", remaining_percent = 57, stale = false },
}
uncertain.accounts_error = "accounts_truncated"
request()
reply(uncertain)
contains(lastBar, "Empty 0% left")
contains(lastBar, "Full 100% left")
contains(lastBar, "Missing Unknown")
contains(lastBar, "Old Stale")
contains(lastBar, "No freshness Stale")
contains(lastBar, "Broken Unavailable")
contains(lastBar, "Rejected Unavailable")
assert(#collectNodes(lastBar, "progress") == 2)
assert(not string.find(texts(lastBar), "42%", 1, true))
assert(not string.find(texts(lastBar), "55%", 1, true))
assert(not string.find(texts(lastBar), "56%", 1, true))
assert(not string.find(texts(lastBar), "57%", 1, true))
tooltipContains("Old: 42% left · stale")
tooltipContains("provider_error")
tooltipContains("quota_unavailable")
tooltipContains("accounts_truncated")

-- Retained accounts remain identifiable on failures, without any live quota meters.
request()
reply("invalid JSON")
contains(lastBar, "offline")
contains(lastBar, "codex · one")
contains(lastBar, "claude · two")
contains(lastBar, "Empty Stale")
assert(#collectNodes(lastBar, "progress") == 0)

local duplicates = sample()
duplicates.accounts = {
    { id = "first-account", provider = "codex", account = "Default", windows = {} },
    { id = "other-account", provider = "codex", account = "Default", windows = {} },
}
request()
reply(duplicates)
contains(lastBar, "codex · Default · first-ac")
contains(lastBar, "codex · Default · other-ac")
tooltipContains("first-accoun")
assert(#collectNodes(lastBar, "progress") == 0)

request()
reply({ version = 1, online = true, error = "", sessions = {}, accounts = {} })
contains(lastBar, "No connected accounts")
assert(not string.find(texts(lastBar), "codex", 1, true), "Disconnected accounts must disappear")

request()
reply({
    version = 1,
    online = true,
    error = "auth_unavailable",
    accounts_error = "auth_unavailable",
    sessions = {},
    accounts = {},
})
contains(lastBar, "Account data unavailable")
assert(not string.find(texts(lastBar), "No connected accounts", 1, true))
tooltipContains("auth_unavailable")

for _, case in ipairs({
    { value = 60, interval = 60000 },
    { value = 1000, interval = 300000 },
    { value = "invalid", interval = 60000 },
    { interval = 60000 },
}) do
    config.refreshIntervalSec = case.value
    request()
    assert(interval == case.interval, "Refresh interval default or clamp changed")
    reply(sample())
end

print(
    "Albedo monitor: minute polling, all-account/window bar meters, tooltips, lifecycle, stale/error recovery, bounds, normalization and theme radius passed"
)
