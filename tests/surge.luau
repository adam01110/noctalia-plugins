--!nonstrict

local state, watchers = {}, {}
local pending, command, interval, visible, bar, tooltip, renderedPanel, selectedPanel
local started = 0
local accepted = true
local scale = 1
local config = { surgePath = "/tmp/space ' ; $/surge", host = "127.0.0.1:1700" }
local noctalia = {
    getConfig = function(key)
        return config[key]
    end,
    getSetting = function(key)
        assert(key == "shell.corner_radius_scale")
        return scale
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
scale = 0
refresh()
assert(pending ~= nil)
reply({ item("a", "downloading", 100, 200, -10) })
assert(find(bar, "progress").props.radius == 0)
assert(find(bar, "progress").props.progress == 1)
assert(state.downloads.items[1].speed == 0)
request()
reply({ item("unknown", "downloading", 0, 0, 12) })
assert(visible == true and find(bar, "progress") == nil)
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
onClose()
print("Surge service/bar/panel checks passed")
