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
local panel = {
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

assert(visible == false and interval == 2000)
assert(command[1] == "timeout" and command[2] == "5s")
assert(command[3] == config.surgePath and command[4] == "ls" and command[5] == "--json")
assert(command[6] == "--host" and command[7] == config.host)
serviceUpdate()
assert(started == 1, "Overlapping polls must be suppressed")
reply({})
assert(visible == false)
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
assert(visible == false)
for _, failure in ipairs({ { exitCode = 1 }, { timedOut = true }, { stdoutTruncated = true } }) do
    request()
    reply({ item("active", "downloading", 2, 1, 0) })
    assert(visible == true)
    request()
    reply({}, failure)
    assert(visible == false and #state.downloads.items == 0 and state.downloads.error ~= "")
    assert(#state.downloads.speedHistory == 0 and find(renderedPanel, "graph") == nil)
    assert(hasText(renderedPanel, "Server unavailable"))
end
for _, malformed in ipairs({ "invalid", { error = "failed" }, { 9 }, { { id = "a" } } }) do
    request()
    reply(malformed)
    assert(visible == false and state.downloads.error == "Invalid Surge response")
end
accepted = false
serviceUpdate()
assert(visible == false and state.downloads.error == "Could not run Surge")
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
onClose()
print(
    "Surge service/bar/panel: bounded history, graph, cards, theme geometry, recovery and idle checks passed"
)
