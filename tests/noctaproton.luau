--!nonstrict

local settings = {}
local lastPanel, watcher, toggled, command
local snapshot = {
    connected = true,
    signedIn = true,
    busy = false,
    server = "US#1",
    country = "US",
    city = "City",
    ip = "127.0.0.1",
    config = { killSwitch = "off", netshield = "off", portForwarding = "on" },
    forwardedPort = 1234,
    splitTunneling = { available = true, enabled = true, apps = { "/bin/app" }, candidates = {} },
    countries = { { code = "US", name = "United States" }, { code = "NL", name = "Netherlands" } },
    traffic = {},
    account = { username = "user", plan = "paid" },
}
local noctalia = {
    getSetting = function(key)
        return settings[key]
    end,
    tr = function(key)
        return key
    end,
    string = {
        trim = function(value)
            return value
        end,
    },
    togglePanel = function(id)
        toggled = id
    end,
    state = {
        get = function()
            return snapshot
        end,
        set = function(_, value)
            command = value
        end,
        watch = function(_, callback)
            watcher = callback
        end,
    },
}
local ui = setmetatable({}, {
    __index = function(_, kind)
        return function(props, children)
            return { kind = kind, props = props or {}, children = children or {} }
        end
    end,
})
local panel = {
    render = function(node)
        lastPanel = node
    end,
}
local barWidget = setmetatable({}, {
    __index = function()
        return function() end
    end,
})

local function loadPanel()
    -- PANEL_SOURCE
end
loadPanel()

local function button(node, text)
    if node.kind == "button" and (node.props.text == text or node.props.glyph == text) then
        return node.props
    end
    for _, child in ipairs(node.children) do
        local result = button(child, text)
        if result then
            return result
        end
    end
end

local function checkSurfaces(node, scale, width, color)
    if node.props.radius ~= nil then
        assert(
            node.props.radius >= 0 and node.props.radius <= 16 * scale,
            "Radius must track user scale"
        )
        if scale == 0 then
            assert(node.props.radius == 0, "Square corners must remain square")
        end
        assert(
            node.props.borderWidth == width,
            "Surface must respect configured border width/enablement"
        )
        assert(node.props.border == color, "Surface must respect configured border color")
    end
    for _, child in ipairs(node.children) do
        checkSurfaces(child, scale, width, color)
    end
end

local function checkTheme(scale, width, color)
    watcher(snapshot)
    assert(lastPanel.props.radius == 16 * scale)
    assert(lastPanel.children[2].props.radius == 12 * scale)
    for _, tab in ipairs({ "connections", "protection", "account" }) do
        button(lastPanel, "tabs." .. tab).onClick()
        checkSurfaces(lastPanel, scale, width, color)
    end
    snapshot.signedIn = false
    watcher(snapshot)
    checkSurfaces(lastPanel, scale, width, color)
    snapshot.signedIn = true
end

checkTheme(1, 1, "outline")
settings = {
    ["shell.corner_radius_scale"] = 0,
    ["shell.panel.border_width"] = 3,
    ["shell.panel.border_color"] = "primary",
}
checkTheme(0, 3, "primary")
settings["shell.corner_radius_scale"] = 1.5
checkTheme(1.5, 3, "primary")
settings["shell.panel.borders"] = false
checkTheme(1.5, 0, "primary")
settings = {
    ["shell.corner_radius_scale"] = "invalid",
    ["shell.panel.border_width"] = "invalid",
    ["shell.panel.border_color"] = "",
}
checkTheme(1, 1, "outline")
settings = { ["shell.corner_radius_scale"] = -1, ["shell.panel.border_width"] = -1 }
checkTheme(0, 0, "outline")
settings = { ["shell.corner_radius_scale"] = 10, ["shell.panel.border_width"] = 30 }
checkTheme(2, 20, "outline")
settings = { ["shell.corner_radius_scale"] = 0 / 0, ["shell.panel.border_width"] = math.huge }
checkTheme(1, 1, "outline")
button(lastPanel, "x").onClick()
assert(toggled == "adam0/noctaproton-vpn:panel")
button(lastPanel, "tabs.connections").onClick()
button(lastPanel, "actions.fastest").onClick()
assert(command.op == "connect" and command.target == "fastest")

local function loadBar()
    -- BAR_SOURCE
    onClick()
    assert(toggled == "adam0/noctaproton-vpn:panel")
    onRightClick()
    assert(command.op == "disconnect")
end
loadBar()
print(
    "NoctaProton: all tabs, square/scaled corners, configurable/disabled borders, fallback settings and custom panel/actions passed"
)
