--!nonstrict

local state, watchers = {}, {}
local pending, command, interval, visible, bar, tooltip, renderedPanel, selectedPanel
local started = 0
local accepted = true
local scale = 1
local borders, borderWidth, borderColor = true, 2, "outline"
local config = { surgePath = "/tmp/space ' ; $/surge", host = "127.0.0.1:1700" }
local noctalia = {
    getConfig = function(key)
        return config[key]
    end,
    getSetting = function(key)
        if key == "shell.corner_radius_scale" then
            return scale
        elseif key == "shell.panel.borders" then
            return borders
        elseif key == "shell.panel.border_width" then
            return borderWidth
        elseif key == "shell.panel.border_color" then
            return borderColor
        end
        error("Unexpected setting: " .. key)
    end,
    expandPath = function(path)
        return path
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
        assert(timeout == 6000)
        started = started + 1
        command = argv
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
    setVisible = function(value)
        visible = value
    end,
    render = function(value)
        bar = value
    end,
    setTooltip = function(value)
        tooltip = value
    end,
}
local panelClosed = false
local panel = {
    close = function()
        panelClosed = true
        onClose()
    end,
    render = function(value)
        renderedPanel = value
    end,
}

do
    -- SERVICE_SOURCE
end
local serviceUpdate = update

do
    -- STATUS_SOURCE
end
local click, refresh = onClick, onRightClick

do
    -- PANEL_SOURCE
end

local function reply(data, extra)
    local callback = pending
    pending = nil
    assert(callback ~= nil)
    local result = extra or {}
    result.exitCode = result.exitCode or 0
    result.stdout = data
    callback(result)
end
local function request()
    serviceUpdate()
    assert(pending ~= nil)
end
local function item(id, status, total, downloaded, speed)
    return {
        id = id,
        filename = id .. ".iso",
        status = status,
        total_size = total,
        downloaded = downloaded,
        speed = speed,
    }
end
local function find(tree, kind)
    if tree.kind == kind then
        return tree
    end
    for _, child in ipairs(tree.children or {}) do
        local found = find(child, kind)
        if found then
            return found
        end
    end
end

local function findKey(tree, key)
    if tree.props.key == key then
        return tree
    end
    for _, child in ipairs(tree.children or {}) do
        local found = findKey(child, key)
        if found then
            return found
        end
    end
end
local function hasText(tree, text)
    if tree.props.text == text then
        return true
    end
    for _, child in ipairs(tree.children or {}) do
        if hasText(child, text) then
            return true
        end
    end
    return false
end

assert(visible == true and interval == 2000)
assert(command[1] == "timeout" and command[2] == "5s")
assert(command[3] == config.surgePath and command[4] == "ls" and command[5] == "--json")
assert(command[6] == "--host" and command[7] == config.host)
serviceUpdate()
assert(started == 1, "Overlapping polls must be suppressed")
reply({})
assert(visible == true and find(bar, "progress") == nil and find(bar, "label") == nil)
click()
assert(selectedPanel == "adam0/surge:panel", "Idle launcher must open the panel")
request()
reply({
    item("a", "downloading", 100, 25, 1024),
    item("b", "downloading", 300, 175, 2048),
    item("c", "paused", 100, 1, 0),
})
assert(visible == true and #state.downloads.items == 2)
local meter = find(bar, "progress")
assert(meter.props.width == 26 and meter.props.height == 4 and meter.props.progress == 0.5)
assert(meter.props.radius == 2 and bar.props.gap == 6)
assert(find(bar, "glyph").props.size == 15)
assert(find(bar, "label").props.fontSize == 12)
assert(#tooltip == 2 and tooltip[1].key == "a.iso")
click()
assert(selectedPanel == "adam0/surge:panel")
onOpen()
assert(renderedPanel ~= nil and find(renderedPanel, "progress") ~= nil)
local actions = findKey(renderedPanel, "panel-actions").children
assert(#actions == 2 and actions[1].props.glyph == "refresh" and actions[2].props.glyph == "x")
assert(
    actions[2].props.controlSize == actions[1].props.controlSize
        and actions[2].props.tooltip == "Close"
)
actions[2].props.onClick()
assert(panelClosed, "Close button must call the native panel close action")
onOpen()
local graph = find(renderedPanel, "graph")
assert(graph ~= nil and graph.props.height == 76)
assert(#graph.props.values == 2 and graph.props.values[1] == 0 and graph.props.values[2] == 1)
assert(state.downloads.speedHistory[2] == 3072)
assert(hasText(renderedPanel, "3.0 KiB/s") and hasText(renderedPanel, "1s left"))
local speedCard = findKey(renderedPanel, "speed-card")
local downloadCard = findKey(renderedPanel, "download-1-a")
assert(speedCard.props.radius == 12 and speedCard.props.borderWidth == 2)
assert(downloadCard.props.fill == "surface_variant/0.58" and downloadCard.props.padding == 12)
local snapshot = state.downloads.speedHistory
scale = 0
borders = false
refresh()
assert(pending ~= nil)
reply({ item("a", "downloading", 100, 200, -10) })
assert(find(bar, "progress").props.radius == 0)
assert(find(bar, "progress").props.progress == 1)
assert(state.downloads.items[1].speed == 0)
assert(#snapshot == 2, "Published history snapshots must not mutate")
assert(findKey(renderedPanel, "speed-card").props.radius == 0)
assert(findKey(renderedPanel, "speed-card").props.borderWidth == 0)
assert(find(renderedPanel, "progress").props.radius == 0)
assert(hasText(renderedPanel, "ETA —"))
request()
reply({ item("unknown", "downloading", 0, 0, 12) })
assert(visible == true and find(bar, "progress") == nil)
assert(hasText(renderedPanel, "Size unknown") and hasText(renderedPanel, "ETA —"))
assert(find(renderedPanel, "progress") == nil)
request()
reply({
    item("a", "queued", 1, 0, 0),
    item("b", "paused", 1, 0, 0),
    item("c", "completed", 1, 1, 0),
    item("d", "error", 1, 0, 0),
})
assert(visible == true and find(bar, "progress") == nil and find(bar, "label") == nil)
assert(#state.downloads.active == 2 and #state.downloads.history == 2)
assert(hasText(renderedPanel, "Queued") and hasText(renderedPanel, "Paused"))
assert(not hasText(renderedPanel, "Completed") and not hasText(renderedPanel, "Failed"))
findKey(renderedPanel, "tab-history").props.onClick()
assert(findKey(renderedPanel, "tab-history").props.selected == true)
assert(hasText(renderedPanel, "Completed") and hasText(renderedPanel, "Failed"))
assert(not hasText(renderedPanel, "Queued") and not hasText(renderedPanel, "Paused"))
assert(find(renderedPanel, "progress") == nil, "History must not show a live download meter")
onClose()
onOpen()
assert(findKey(renderedPanel, "tab-history").props.selected == true)
local terminalSnapshot = state.downloads.history
request()
reply({}, { exitCode = 1 })
assert(#state.downloads.history == 2 and #terminalSnapshot == 2)
assert(hasText(renderedPanel, "Completed") and hasText(renderedPanel, "Server unavailable"))
assert(hasText(renderedPanel, "Surge server unavailable · Showing last known history"))
assert(visible == true and find(bar, "label") == nil)
findKey(renderedPanel, "tab-active").props.onClick()
assert(hasText(renderedPanel, "No active downloads"))
for _, failure in ipairs({ { exitCode = 1 }, { timedOut = true }, { stdoutTruncated = true } }) do
    request()
    reply({ item("active", "downloading", 2, 1, 0) })
    assert(visible == true)
    request()
    reply({}, failure)
    assert(visible == true and find(bar, "progress") == nil and find(bar, "label") == nil)
    assert(
        #state.downloads.items == 0 and #state.downloads.active == 0 and state.downloads.error ~= ""
    )
    assert(#state.downloads.speedHistory == 0 and find(renderedPanel, "graph") == nil)
    assert(hasText(renderedPanel, "Server unavailable"))
end
for _, malformed in ipairs({ "invalid", { error = "failed" }, { 9 }, { { id = "a" } } }) do
    request()
    reply(malformed)
    assert(
        visible == true
            and find(bar, "label") == nil
            and state.downloads.error == "Invalid Surge response"
    )
end
accepted = false
serviceUpdate()
assert(
    visible == true and find(bar, "label") == nil and state.downloads.error == "Could not run Surge"
)
accepted = true
config.refreshIntervalSec = 500
request()
assert(interval == 60000)
reply({})
config.refreshIntervalSec = 0
request()
assert(interval == 1000)
reply({})
borders, borderWidth, borderColor = true, 3, "primary"
scale = 0 / 0
onClose()
local closedPanel = renderedPanel
for speed = 1, 65 do
    request()
    reply({ item("history", "downloading", 1000, 1, speed) })
end
assert(renderedPanel == closedPanel, "Closed panels must not render on polls")
assert(#state.downloads.speedHistory == 60)
assert(state.downloads.speedHistory[1] == 6 and state.downloads.speedHistory[60] == 65)
onOpen()
graph = find(renderedPanel, "graph")
assert(
    #graph.props.values == 60 and graph.props.values[1] == 6 / 65 and graph.props.values[60] == 1
)
assert(findKey(renderedPanel, "speed-card").props.radius == 12)
assert(findKey(renderedPanel, "speed-card").props.borderWidth == 3)
assert(findKey(renderedPanel, "speed-card").props.border == "primary")
request()
reply({}, { exitCode = 1 })
request()
reply({ item("recovered", "downloading", 1000, 1, 0) })
assert(#state.downloads.speedHistory == 1 and find(renderedPanel, "graph") == nil)
assert(hasText(renderedPanel, "Collecting speed history…"))
request()
reply({ item("recovered", "downloading", 1000, 1, 0) })
graph = find(renderedPanel, "graph")
assert(graph.props.values[1] == 0 and graph.props.values[2] == 0)
local many = {}
for index = 1, 42 do
    many[index] = item(tostring(index), "downloading", 1000000, 10, 1)
end
request()
reply(many)
assert(hasText(renderedPanel, "2 more active downloads"))
assert(findKey(renderedPanel, "download-40-40") ~= nil)
assert(findKey(renderedPanel, "download-41-41") == nil)
local terminal = {}
for index = 1, 105 do
    terminal[index] =
        item(tostring(index), index % 2 == 0 and "completed" or "error", 100, 100, 999)
    terminal[index].added_at = index
end
request()
reply(terminal)
assert(
    #state.downloads.items == 0 and #state.downloads.active == 0 and #state.downloads.history == 100
)
assert(state.downloads.history[1].id == "105" and state.downloads.history[100].id == "6")
assert(state.downloads.history[1].speed == 0)
assert(visible == true and find(bar, "progress") == nil and find(bar, "label") == nil)
assert(hasText(renderedPanel, "No active downloads"), "Completion must leave the panel open")
findKey(renderedPanel, "tab-history").props.onClick()
assert(hasText(renderedPanel, "60 more history entries"))
assert(findKey(renderedPanel, "download-1-105") ~= nil)
request()
reply({})
assert(#state.downloads.history == 0 and hasText(renderedPanel, "No download history"))
request()
reply({ item("retry", "downloading", 100, 10, 20) })
findKey(renderedPanel, "tab-active").props.onClick()
assert(findKey(renderedPanel, "download-1-retry") ~= nil)
request()
reply({ item("retry", "completed", 100, 100, 0) })
assert(hasText(renderedPanel, "No active downloads"))
findKey(renderedPanel, "tab-history").props.onClick()
assert(hasText(renderedPanel, "retry.iso") and hasText(renderedPanel, "Completed"))
onClose()
print(
    "Surge: Active/History tabs, persistent idle launcher, server history, graph, theme and recovery checks passed"
)
