--!nonstrict

local hostOs = os
local now = 1760000000
local os = {
    time = function(date)
        return date ~= nil and hostOs.time(date) or now
    end,
    date = hostOs.date,
}

-- State watchers connect the real entry scripts without starting Noctalia.
local state, watchers = {}, {}
local pending, command, lastBar, lastPanel, lastTooltip, selectedPanel
local started, panelRenders = 0, 0
local accepted = true
local settingReads, cornerScale = 0, 0
local borderSettings = { borders = true, border_width = 1, border_color = "outline" }
local borderReads = {}
local config = { monitorPath = "/tmp/space ' ; $/albedo-monitor" }
local interval
local noctalia = {
    getConfig = function(key)
        return config[key]
    end,
    getSetting = function(key)
        if key == "shell.corner_radius_scale" then
            settingReads = settingReads + 1
            return cornerScale
        end
        local field = string.match(key, "^shell%.panel%.(.+)$")
        assert(field ~= nil)
        borderReads[field] = (borderReads[field] or 0) + 1
        return borderSettings[field]
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
                        resets_at_epoch = now + 7200,
                        observed_at = hostOs.date("!%Y-%m-%dT%H:%M:%SZ", now),
                        stale = false,
                    },
                    { label = "Weekly", remaining_percent = 0, stale = true },
                },
            },
            { provider = "claude", account = "two", error = "quota_unavailable", windows = {} },
        },
    }
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

assert(started == 1 and interval == 60000, "Default refresh must be one minute")
assert(type(command) == "table" and command[1] == "timeout" and command[2] == "12s")
assert(command[3] == config.monitorPath and #command == 4, "Path must stay one literal argument")
assert(command[4] == "--start-daemon", "Widget must opt into bounded native daemon startup")
serviceUpdate()
assert(started == 1, "Requests must not overlap")
contains(lastBar, "offline")
reply(sample())
assert(state.snapshot.sessions[1].status == "working")
assert(lastBar.children[2].props.text == "2" and lastBar.children[2].props.color == "primary")
contains(lastBar, "63%")
assert(#collectNodes(lastBar, "progress") == 1)
assert(not string.find(texts(lastBar), " left", 1, true))
assert(not string.find(texts(lastBar), " active", 1, true))
local function assertReadableText(tree)
    local labels = collectNodes(tree, "label")
    assert(#labels > 0, "Typography checks need a rendered tree")
    for _, node in ipairs(labels) do
        assert(node.props.fontSize >= 12, "Rendered text must stay at least 12px")
    end
end
assertReadableText(lastBar)
assert(not string.find(texts(lastBar), "codex", 1, true), "Identity belongs in hover details")
tooltipContains("codex · one")
tooltipContains("claude · two")
tooltipContains("Weekly: 0% · stale")
assert(not string.find(texts(lastBar), "0%", 1, true), "Stale quota cannot look current")
assert(panelRenders == 0, "Closed panels must not render")
statusClick()
assert(selectedPanel == "adam0/albedo-monitor:panel")
onOpen({})
assertReadableText(lastPanel)
contains(lastPanel, "DAEMON ONLINE")
contains(lastPanel, "↳ Child")
contains(lastPanel, "quota_unavailable")
contains(lastPanel, "Quota unavailable")
contains(lastPanel, "0% · stale")
contains(lastPanel, "Resets in 2h 0m")
assert(not string.find(texts(lastPanel), "Observed", 1, true))
assert(not string.find(texts(lastPanel), "Unknown does not mean unlimited", 1, true))
assert(not string.find(texts(lastPanel), "2026-10-17", 1, true))
assert(not string.find(texts(lastPanel), "Idle", 1, true), "Idle conversations must not be listed")
local sessionCards = 0
for _, node in ipairs(collectNodes(lastPanel, "column")) do
    if node.props.key and string.sub(node.props.key, 1, 8) == "session-" then
        sessionCards = sessionCards + 1
    end
end
assert(sessionCards == 3, "Show working and waiting sessions, not every conversation")
assert(pending ~= nil, "Opening panel requests fresh snapshot")
reply("invalid JSON", 1)
assert(state.snapshot.stale and not state.snapshot.online)
assert(#state.snapshot.sessions == 4, "Keep last data only as explicitly stale")
contains(lastBar, "offline")
assert(lastBar.children[2].props.text == "offline", "Stale sessions must not appear active")
contains(lastPanel, "showing last known data")
assert(not string.find(texts(lastPanel), "↳ Child", 1, true), "Offline sessions are not active")

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
assert(lastBar.children[2].props.text == "2" and lastBar.children[2].props.color == "primary")
assert(state.snapshot.error == "" and not state.snapshot.stale)

local partial = sample()
partial.error = "sessions_truncated"
partial.sessions = {}
request()
reply(partial)
contains(lastBar, "status unavailable")
contains(lastBar, "63%")
contains(lastPanel, "PARTIAL SNAPSHOT")
contains(lastPanel, "Session status unavailable")
assert(not string.find(texts(lastPanel), "No active sessions", 1, true))
assert(lastBar.children[2].props.text == "status unavailable")

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
assert(windows[1].remaining_percent == nil and windows[2].remaining_percent == nil)
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
assert(lastBar.children[2].props.text == "100")
contains(lastPanel, "40 more active sessions")
onClose()
local renders = panelRenders
request()
reply(sample())
assert(panelRenders == renders, "Closed panel received update")
statusRefresh()
assert(pending ~= nil)
reply({ version = 1, online = true, sessions = {}, accounts = {} })
assert(lastBar.children[2].props.text == "0")
assert(lastBar.children[2].props.color == "on_surface_variant")
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
    checkProgressRadius(lastPanel, case.radius, 1)
    checkProgressRadius(lastBar, case.radius, 1)
    local scale = case.radius / 2
    assert(
        lastPanel.props.border == nil and lastPanel.props.borderWidth == nil,
        "Popup shell supplies the outer border"
    )
    assert(lastPanel.props.radius == 16 * scale, "Popup radius must follow the user setting")
    local cards = 0
    for _, node in ipairs(collectNodes(lastPanel, "column")) do
        local key = node.props.key or ""
        if string.sub(key, 1, 8) == "session-" then
            assert(node.props.radius == 10 * scale and node.props.fill == "surface_variant/0.58")
            assert(node.props.border == "outline" and node.props.borderWidth == 1)
            cards = cards + 1
        elseif string.sub(key, 1, 8) == "account-" then
            assert(node.props.radius == 12 * scale and node.props.padding == 12)
            assert(node.props.border == "outline" and node.props.borderWidth == 1)
            cards = cards + 1
        end
    end
    assert(cards == 5, "Three active session cards and two account cards")
    local buttons = collectNodes(lastPanel, "button")
    assert(#buttons == 2)
    for _, button in ipairs(buttons) do
        assert(
            button.props.variant == nil and button.props.controlSize == "sm",
            "Use native button surface"
        )
    end
    assert(buttons[1].props.onClick == "onRefresh" and buttons[2].props.onClick == "onCloseClicked")
end

-- Cards inherit panel border settings; the popup shell is bordered by Noctalia.
for _, case in ipairs({
    {
        settings = { borders = true, border_width = 2.5, border_color = "primary" },
        width = 2.5,
        color = "primary",
    },
    {
        settings = { borders = false, border_width = 3, border_color = "#abcdef" },
        width = 0,
        color = "#abcdef",
    },
    {
        settings = { borders = true, border_width = 0, border_color = "secondary" },
        width = 0,
        color = "secondary",
    },
    { settings = { border_width = -1 }, width = 0, color = "outline" },
    { settings = { border_width = 25 }, width = 20, color = "outline" },
    { settings = { border_width = "invalid", border_color = "" }, width = 1, color = "outline" },
    { settings = { border_width = math.huge }, width = 1, color = "outline" },
    { settings = { border_width = 0 / 0 }, width = 1, color = "outline" },
    { settings = {}, width = 1, color = "outline" },
}) do
    borderSettings = case.settings
    borderReads = {}
    noctalia.state.set("snapshot", state.snapshot)
    assert(lastPanel.props.borderWidth == nil and lastPanel.props.border == nil)
    local cards = 0
    for _, node in ipairs(collectNodes(lastPanel, "column")) do
        local key = node.props.key or ""
        if string.sub(key, 1, 8) == "session-" or string.sub(key, 1, 8) == "account-" then
            assert(node.props.borderWidth == case.width and node.props.border == case.color)
            cards = cards + 1
        end
    end
    assert(cards == 5)
    assert(
        borderReads.borders == 1 and borderReads.border_width == 1 and borderReads.border_color == 1
    )
end
borderSettings = { borders = true, border_width = 1, border_color = "outline" }

-- Keep all accounts, but show only one healthy window per account.
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
                observed_at = hostOs.date("!%Y-%m-%dT%H:%M:%SZ", now),
            },
            { label = "Weekly", remaining_percent = 100 - index, stale = false },
        },
    }
end
request()
reply(inventory)
for index = 1, 6 do
    contains(lastBar, tostring(index * 10) .. "%")
    assert(not string.find(texts(lastBar), tostring(100 - index) .. "%", 1, true))
    tooltipContains("public-" .. tostring(index))
end
local meters = collectNodes(lastBar, "progress")
assert(#meters == 6, "Render one limiting window for each account")
assert(meters[1].props.progress == 0.1 and meters[1].props.fill == "error")
assert(meters[2].props.progress == 0.2 and meters[2].props.fill == "tertiary")
assert(meters[4].props.progress == 0.4 and meters[4].props.fill == "primary")
assert(meters[1].props.width == 26 and meters[1].props.height == 4)
tooltipContains("Bar · Session:")
tooltipContains("Weekly:")
assert(not string.find(tooltipText(), "Observed", 1, true))
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
contains(lastBar, "0%")
assert(not string.find(texts(lastBar), "100%", 1, true))
tooltipContains("Full: 100%")
tooltipContains("Missing: Unknown")
tooltipContains("Old: 42% · stale")
tooltipContains("No freshness: 55% · stale")
tooltipContains("Broken: Unavailable")
tooltipContains("Rejected: Unavailable")
assert(#collectNodes(lastBar, "progress") == 1)
assert(not string.find(texts(lastBar), "42%", 1, true))
assert(not string.find(texts(lastBar), "55%", 1, true))
assert(not string.find(texts(lastBar), "56%", 1, true))
assert(not string.find(texts(lastBar), "57%", 1, true))
tooltipContains("Old: 42% · stale")
tooltipContains("provider_error")
tooltipContains("quota_unavailable")
tooltipContains("accounts_truncated")

-- Retained accounts remain identifiable on failures, without any live quota meters.
request()
reply("invalid JSON")
contains(lastBar, "offline")
tooltipContains("codex · one")
tooltipContains("claude · two")
tooltipContains("Empty: 0% · stale")
assert(#collectNodes(lastBar, "progress") == 0)

local duplicates = sample()
duplicates.accounts = {
    { id = "first-account", provider = "codex", account = "Default", windows = {} },
    { id = "other-account", provider = "codex", account = "Default", windows = {} },
}
request()
reply(duplicates)
tooltipContains("codex · Default · first-accoun")
tooltipContains("codex · Default · other-accoun")
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

-- Usage states are not transport errors: depletion is a known zero balance.
for _, case in ipairs({
    { status = "warning", remaining = 9 },
    { status = "exhausted", remaining = 0 },
}) do
    local depleted = sample()
    depleted.accounts[1].windows[1].status = case.status
    depleted.accounts[1].windows[1].remaining_percent = case.remaining
    request()
    reply(depleted)
    contains(lastBar, tostring(case.remaining) .. "%")
    local meters = collectNodes(lastBar, "progress")
    assert(#meters == 1 and meters[1].props.progress == case.remaining / 100)
    assert(meters[1].props.fill == "error")
    contains(lastPanel, tostring(case.remaining) .. "%")
    tooltipContains("Bar · Session: " .. tostring(case.remaining) .. "%")
end

-- Older helpers reject the new flag on stderr; retry without publishing false offline data.
local beforeCompatibility = panelRenders
request()
local oldHelper = pending
pending = nil
oldHelper({
    exitCode = 2,
    stdout = "",
    stderr = "albedo-monitor: error: unrecognized arguments: --start-daemon\n",
})
assert(#command == 3 and command[3] == config.monitorPath)
assert(pending ~= nil, "Retry the legacy helper immediately")
assert(panelRenders == beforeCompatibility, "Do not flash an offline snapshot on negotiation")
reply(sample())
assert(state.snapshot.online and not state.snapshot.stale)
assert(lastBar.children[2].props.text == "2")
request()
assert(#command == 3, "Remember compatibility for the installed helper path")
reply(sample())
local originalPath = config.monitorPath
config.monitorPath = "/tmp/new monitor/albedo-monitor"
request()
assert(#command == 4 and command[4] == "--start-daemon", "Reprobe a different helper")
reply(sample())
config.monitorPath = originalPath

for index, failure in ipairs({
    { exitCode = 2, stdout = "", stderr = "unrecognized arguments: --timeout" },
    {
        exitCode = 2,
        stdout = "",
        stderr = "unrecognized arguments: --start-daemon",
        stderrTruncated = true,
    },
    {
        exitCode = 2,
        stdout = "",
        stderr = "unrecognized arguments: --start-daemon",
        timedOut = true,
    },
}) do
    config.monitorPath = "/tmp/modern-monitor-" .. tostring(index)
    local beforeFailure = started
    request()
    local callback = pending
    pending = nil
    callback(failure)
    assert(
        pending == nil and started == beforeFailure + 1,
        "Do not retry unrelated or incomplete failures"
    )
    assert(not state.snapshot.online)
end
config.monitorPath = originalPath
request()
reply(sample())

local waitingOnly = sample()
waitingOnly.sessions = {
    { id = "hidden-idle", title = "Hidden idle", status = "idle" },
    { id = "hidden-unknown", title = "Hidden unknown", status = "unknown" },
    { id = "needs-input", title = "Approval needed", status = "waiting" },
}
request()
reply(waitingOnly)
assert(lastBar.children[2].props.text == "0")
assert(lastBar.children[2].props.color == "on_surface_variant")
contains(lastPanel, "Approval needed")
assert(not string.find(texts(lastPanel), "Hidden idle", 1, true))
assert(not string.find(texts(lastPanel), "Hidden unknown", 1, true))
waitingOnly.sessions[3] = nil
request()
reply(waitingOnly)
contains(lastPanel, "No active sessions")
assert(not string.find(texts(lastPanel), "Hidden", 1, true))

local limiting = sample()
limiting.accounts[1].windows = {
    { label = "Session", remaining_percent = 80, stale = false },
    { label = "Weekly", remaining_percent = 13, stale = false },
    { label = "Expired", remaining_percent = 1, stale = false, resets_at_epoch = now - 1 },
}
request()
reply(limiting)
assert(#collectNodes(lastBar, "progress") == 1)
assert(collectNodes(lastBar, "progress")[1].props.progress == 0.8)
contains(lastBar, "80%")
assert(not string.find(texts(lastBar), "13%", 1, true))
tooltipContains("Bar · Session: 80%")

for _, labels in ipairs({
    { "5 hours", "7 days" },
    { "5h", "7d" },
    { "Session", "Weekly" },
    { "5h window", "7d window" },
}) do
    for _, case in ipairs({
        { weekly = 13, session = 80, expected = 80 },
        { weekly = 5.01, session = 80, expected = 80 },
        { weekly = 5, session = 80, expected = 5 },
        { weekly = 4.99, session = 80, expected = 4.99 },
        { weekly = 0, session = 80, expected = 0 },
        { weekly = 4, session = 1, expected = 4 },
        { weekly = 4, session = 80, weeklyStale = true, expected = 80 },
        { weekly = 4, session = 80, weeklyStatus = "unavailable", expected = 80 },
        { weekly = 4, session = 80, weeklyReset = now - 1, expected = 80 },
        { weekly = 13, session = 80, sessionStale = true, expected = 13 },
    }) do
        local priority = sample()
        priority.accounts[1].windows = {
            {
                label = labels[2],
                remaining_percent = case.weekly,
                stale = case.weeklyStale or false,
                status = case.weeklyStatus or "ok",
                resets_at_epoch = case.weeklyReset,
            },
            {
                label = labels[1],
                remaining_percent = case.session,
                stale = case.sessionStale or false,
            },
        }
        request()
        reply(priority)
        local progress = collectNodes(lastBar, "progress")
        assert(#progress == 1 and progress[1].props.progress == case.expected / 100)
        local selected = case.expected == case.session and labels[1] or labels[2]
        tooltipContains("Bar · " .. selected .. ":")
    end
end
assert(not string.find(texts(lastBar), " left", 1, true))
assert(not string.find(texts(lastPanel), " left", 1, true))

for _, case in ipairs({
    { seconds = 2 * 86400 + 3 * 3600, text = "Resets in 2d 3h" },
    { seconds = 3 * 3600 + 45 * 60, text = "Resets in 3h 45m" },
    { seconds = 12 * 60, text = "Resets in 12m" },
    { seconds = 59, text = "Resets in 1m" },
    { seconds = 0, text = "Reset passed · awaiting provider update" },
    { seconds = -60, text = "Reset passed · awaiting provider update" },
}) do
    local deadline = sample()
    deadline.accounts[1].windows[1].resets_at_epoch = now + case.seconds
    request()
    reply(deadline)
    contains(lastPanel, case.text)
    assert(not string.find(texts(lastPanel), "Observed", 1, true))
end

local clocked = sample()
clocked.accounts[1].windows[1].resets_at_epoch = now + 7200
request()
reply(clocked)
contains(lastPanel, "Resets in 2h 0m")
now = now + 60
noctalia.state.set("snapshot", state.snapshot)
contains(lastPanel, "Resets in 1h 59m")

for _, epoch in ipairs({ "invalid", "1760000000", true, math.huge, -math.huge, 0 / 0 }) do
    local invalidDeadline = sample()
    invalidDeadline.accounts[1].windows[1].resets_at_epoch = epoch
    request()
    reply(invalidDeadline)
    assert(state.snapshot.accounts[1].windows[1].resets_at_epoch == nil)
    contains(lastPanel, "Reset unavailable")
end

-- Legacy snapshots have a reset ISO string but no numeric deadline field.
for _, case in ipairs({
    { value = "2026-10-23T12:00:00Z", epoch = 1792756800 },
    { value = "2026-10-23T14:00:00+02:00", epoch = 1792756800 },
    { value = "2026-10-23T05:00:00-07:00", epoch = 1792756800 },
    { value = "2026-10-23T12:00:00.123Z", epoch = 1792756800 },
    { value = "2026-03-29T01:30:00Z", epoch = 1774747800 },
    { value = "2026-10-25T01:30:00Z", epoch = 1792891800 },
}) do
    local legacy = sample()
    legacy.accounts[1].windows[1].resets_at_epoch = nil
    legacy.accounts[1].windows[1].resets_at = case.value
    request()
    reply(legacy)
    assert(
        state.snapshot.accounts[1].windows[1].resets_at_epoch == case.epoch,
        "Legacy reset parsing changed"
    )
    assert(not string.find(texts(lastPanel), "Reset unavailable", 1, true))
end
local relativeLegacy = sample()
relativeLegacy.accounts[1].windows[1].resets_at_epoch = nil
relativeLegacy.accounts[1].windows[1].resets_at = hostOs.date("!%Y-%m-%dT%H:%M:%SZ", now + 7200)
request()
reply(relativeLegacy)
contains(lastPanel, "Resets in 2h 0m")

for _, value in ipairs({
    "invalid",
    "2026-02-30T12:00:00Z",
    "2026-10-23T25:00:00Z",
    "2026-10-23T12:00:00",
    "2026-10-23T12:00:00+25:00",
    "0000-01-01T00:00:00Z",
}) do
    local invalid = sample()
    invalid.accounts[1].windows[1].resets_at_epoch = nil
    invalid.accounts[1].windows[1].resets_at = value
    request()
    reply(invalid)
    assert(state.snapshot.accounts[1].windows[1].resets_at_epoch == nil)
    contains(lastPanel, "Reset unavailable")
end

-- A missing native callback cannot wedge the plugin or let an old reply win.
request()
local abandonedReply = pending
pending = nil
now = now + 16
request()
reply(sample())
local recoveredSnapshot = state.snapshot
abandonedReply({
    exitCode = 0,
    stdout = { version = 1, online = false, sessions = {}, accounts = {} },
})
assert(state.snapshot == recoveredSnapshot and state.snapshot.online)

-- A new daemon snapshot is not a new provider observation.
local oldQuota = sample()
oldQuota.accounts = { oldQuota.accounts[1] }
oldQuota.accounts[1].windows = {
    {
        label = "5h window",
        remaining_percent = 0,
        status = "exhausted",
        stale = false,
        observed_at_epoch = now - 4 * 86400,
        resets_at_epoch = now - 3600,
    },
}
request()
reply(oldQuota)
contains(lastBar, "Stale")
contains(lastPanel, "Last known 0% · stale")
contains(lastPanel, "Quota checked 4d ago")
contains(lastPanel, "Reset passed · awaiting provider update")
assert(#collectNodes(lastPanel, "progress") == 0)
assert(#collectNodes(lastBar, "progress") == 0)
assert(not string.find(texts(lastPanel), "exhausted", 1, true))
assert(not string.find(texts(lastPanel), "Resetting now", 1, true))

local futureQuota = sample()
futureQuota.accounts = { futureQuota.accounts[1] }
futureQuota.accounts[1].windows = {
    { label = "Session", remaining_percent = 50, stale = false, observed_at_epoch = now + 120 },
}
request()
reply(futureQuota)
contains(lastBar, "Stale")
contains(lastPanel, "Quota check time is in the future")
assert(#collectNodes(lastPanel, "progress") == 0)

-- Cached data ages out even when a request is still running.
local aging = sample()
aging.accounts = { aging.accounts[1] }
aging.accounts[1].windows = {
    { label = "Session", remaining_percent = 63, stale = false, observed_at_epoch = now - 1795 },
}
request()
reply(aging)
contains(lastBar, "63%")
request()
local requestsBeforeExpiry = started
now = now + 10
serviceUpdate()
assert(started == requestsBeforeExpiry, "Expiry cannot overlap requests")
contains(lastBar, "Stale")
assert(#collectNodes(lastPanel, "progress") == 0)
reply(aging)
contains(lastBar, "Stale")
aging.accounts[1].windows[1].observed_at_epoch = now
request()
reply(aging)
contains(lastBar, "63%")
assert(#collectNodes(lastPanel, "progress") == 1)

print(
    "Albedo monitor: minute polling, relevant account meters, active sessions, countdowns, startup argv, recovery and themed cards passed"
)
