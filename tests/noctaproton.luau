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
    onOpen()
    assert(command.op == "refresh_status", "Panel open must refresh cached account/settings")
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

local function checkButtons(node)
    if node.kind == "button" then
        if node.props.glyph and not node.props.text then
            assert(
                node.props.fontSize == nil,
                "Icon-only buttons must not create an empty text label"
            )
        else
            assert(node.props.fontSize == 12, "Buttons must use compact text")
        end
        assert(node.props.controlSize == "sm", "Buttons must use the native small height")
        assert(node.props.variant ~= "outline", "Idle buttons must use the native surface variant")
    end
    for _, child in ipairs(node.children) do
        checkButtons(child)
    end
end

local function checkTheme(scale, width, color)
    watcher(snapshot)
    assert(lastPanel.props.radius == nil, "Native panel shell owns popup radius")
    assert(
        lastPanel.props.borderWidth == nil and lastPanel.props.border == nil,
        "Native panel shell owns popup outline"
    )
    assert(
        button(lastPanel, "refresh").variant == nil and button(lastPanel, "x").variant == nil,
        "Header buttons need native surfaces"
    )
    assert(lastPanel.children[2].props.radius == 12 * scale)
    for _, tab in ipairs({ "connections", "protection", "account" }) do
        button(lastPanel, "tabs." .. tab).onClick()
        if tab == "connections" then
            assert(button(lastPanel, "Random").variant == "ghost")
        end
        checkSurfaces(lastPanel, scale, width, color)
        checkButtons(lastPanel)
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
snapshot.connected = false
watcher(snapshot)
button(lastPanel, "actions.quick_connect").onClick()
assert(command.op == "connect" and command.target == "fastest")
snapshot.connected = true
watcher(snapshot)

local function nodeByKey(node, key)
    if node.props.key == key then
        return node
    end
    for _, child in ipairs(node.children) do
        local found = nodeByKey(child, key)
        if found then
            return found
        end
    end
end

local function checkReadable(node)
    if node.kind == "label" and node.props.fontSize then
        assert(
            node.props.fontSize >= 11 and node.props.fontSize <= 15,
            "Keep panel text compact: 11–15px"
        )
    end
    for _, child in ipairs(node.children) do
        checkReadable(child)
    end
end

settings = {}
for _, tab in ipairs({ "connections", "protection", "account" }) do
    button(lastPanel, "tabs." .. tab).onClick()
    checkReadable(lastPanel)
    assert(lastPanel.props.padding == 8 and lastPanel.props.gap == 8, "Use compact outer spacing")
    assert(button(lastPanel, "tabs." .. tab).glyph == nil, "Text tabs must reserve room for labels")
end
assert(nodeByKey(lastPanel, "account-scroll"), "Account content must scroll")
button(lastPanel, "tabs.protection").onClick()
for _, key in ipairs({ "killswitch", "netshield", "port-forwarding", "split-tunneling" }) do
    local card = nodeByKey(lastPanel, "protection-" .. key)
    assert(
        card and card.props.radius == 8 and card.props.borderWidth == 1,
        "Each protection entry needs its own themed card"
    )
    assert(card.props.padding == 8, "Protection cards need compact padding")
end
local mode = nodeByKey(lastPanel, "netshield-mode")
assert(
    mode and mode.kind == "select" and mode.props.controlSize == "sm",
    "NetShield modes should occupy one compact control"
)
for index, value in ipairs({ "off", "malware-only", "malware-ads-trackers" }) do
    mode.props.onChange(tostring(index - 1))
    assert(command.op == "set_netshield" and command.value == value)
    snapshot.config.netshield = value
    watcher(snapshot)
    assert(nodeByKey(lastPanel, "netshield-mode").props.selectedIndex == index - 1)
end
local before = command
mode.props.onChange("invalid")
mode.props.onChange(4)
assert(command == before, "Invalid NetShield selection must not send commands")
snapshot.busy = true
watcher(snapshot)
assert(not nodeByKey(lastPanel, "netshield-mode").props.enabled)
snapshot.busy = false
snapshot.config.netshield = "off"
watcher(snapshot)
button(lastPanel, "tabs.connections").onClick()
assert(button(lastPanel, "actions.fastest") == nil, "Do not repeat the primary fastest action")
assert(nodeByKey(lastPanel, "country-search").props.controlSize == "sm")
local country = nodeByKey(lastPanel, "country-NL")
assert(
    country.props.borderWidth == 1 and country.props.radius == 8,
    "Each country needs a themed entry card"
)
local connect = button(country, "player-play")
assert(connect.text == nil and connect.tooltip:find("Netherlands", 1, true))
connect.onClick()
assert(command.op == "connect" and command.target == "NL")
for _, target in ipairs({ { "Random", "random" }, { "P2P", "p2p" }, { "Tor", "tor" } }) do
    button(lastPanel, target[1]).onClick()
    assert(command.op == "connect" and command.target == target[2])
end
onSearchChange("nether")
assert(nodeByKey(lastPanel, "country-NL") and not nodeByKey(lastPanel, "country-US"))
onSearchChange("not-a-country")
assert(not nodeByKey(lastPanel, "countries-scroll"))
onSearchChange(42)
assert(nodeByKey(lastPanel, "country-US"), "Invalid input must clear the filter")
for _, state in ipairs({ "busy", "connecting", "signedOut" }) do
    snapshot.busy = state == "busy"
    snapshot.connecting = state == "connecting"
    snapshot.signedIn = state ~= "signedOut"
    watcher(snapshot)
    assert(not button(lastPanel, "Random").enabled)
    assert(not button(nodeByKey(lastPanel, "country-NL"), "player-play").enabled)
end
snapshot.connected = false
watcher(snapshot)
button(lastPanel, "actions.signin").onClick()
assert(nodeByKey(lastPanel, "signin-username-input"), "Sign In must open Account")
checkReadable(lastPanel)
snapshot.connected = true
snapshot.connecting = false
snapshot.busy = false
snapshot.signedIn = true
watcher(snapshot)

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

do
    local pending, calls = {}, {}
    local serviceState, commandWatcher, update, networkEvent
    local publications = 0
    local trafficEnabled = true
    local nmCommand = "nmcli -t -f NAME,TYPE,DEVICE,STATE connection show --active"
    local link = ""
    local trafficReads = 0
    local now = 1000
    local os = {
        time = function()
            return now
        end,
    }
    local noctalia = {
        setUpdateInterval = function(ms)
            assert(ms == 1000)
        end,
        getConfig = function(key)
            if key == "traffic_monitoring" then
                return trafficEnabled
            end
            if key == "notify_on_connect" then
                return false
            end
        end,
        pluginDir = function()
            return "/plugin"
        end,
        expandPath = function(path)
            return path
        end,
        readFile = function(path)
            if path:find("/statistics/", 1, true) then
                trafficReads += 1
                return tostring(now * 100)
            end
            return nil
        end,
        string = {
            trim = function(s)
                return s:match("^%s*(.-)%s*$")
            end,
        },
        json = {
            decode = function()
                return nil
            end,
        },
        state = {
            set = function(_, value)
                serviceState = value
                publications += 1
            end,
            watch = function(_, callback)
                commandWatcher = callback
            end,
        },
        runStream = function(cmd, callback)
            assert(cmd == "sh '/plugin/monitor.sh'")
            networkEvent = callback
            return true
        end,
        runAsync = function(cmd, callback)
            calls[cmd] = (calls[cmd] or 0) + 1
            table.insert(pending, { cmd = cmd, callback = callback })
        end,
    }
    local function loadService()
        -- SERVICE_SOURCE
    end
    local function drain()
        local count = 0
        while #pending > 0 do
            count += 1
            assert(count < 100, "Unbounded async work")
            local job = table.remove(pending, 1)
            local out = ""
            if job.cmd:find("nmcli", 1, true) then
                out = link
            elseif job.cmd == "protonvpn info" then
                out = "Account: 'user'"
            elseif job.cmd == "protonvpn status" then
                out = "Country: US\nServer: different-cli-server-label"
            elseif job.cmd == "protonvpn config list" then
                out = "Netshield: off"
            end
            job.callback({ exitCode = 0, stdout = out, stderr = "" })
        end
    end
    local function tick(count)
        for _ = 1, count do
            now += 1
            update()
            drain()
        end
    end
    loadService()
    drain()
    assert(calls["protonvpn info"] == 1)
    local initialPublications = publications
    tick(600)
    assert(
        calls["protonvpn info"] == 1
            and calls["protonvpn status"] == 1
            and calls["protonvpn config list"] == 1,
        "Ten disconnected minutes must not launch Proton queries"
    )
    assert(calls[nmCommand] == 1, "Idle NetworkManager must not be polled")
    assert(
        publications == initialPublications,
        "Disconnected idle ticks must not republish unchanged state"
    )
    assert(trafficReads == 0, "Disconnected VPN must not read traffic counters")
    for _ = 1, 20 do
        networkEvent("unrelated wifi change")
    end
    tick(2)
    assert(calls[nmCommand] == 2, "Network event bursts must coalesce")
    assert(calls["protonvpn info"] == 1, "Unrelated changes must not launch Proton queries")

    link = "ProtonVPN US#1:wireguard:proton0:activated"
    networkEvent("VPN activated")
    tick(3)
    assert(
        serviceState.connected and calls["protonvpn info"] == 2,
        "External connections must refresh metadata promptly"
    )
    assert(trafficReads > 0)
    local connectedPublications = publications
    tick(600)
    assert(
        calls["protonvpn info"] == 2,
        "Stable connected links must not launch periodic Proton queries"
    )
    assert(
        publications > connectedPublications and serviceState.traffic.rxRate > 0,
        "Connected traffic must still be published"
    )
    networkEvent("resync")
    tick(2)
    assert(
        calls["protonvpn info"] == 2,
        "Stable links must not refresh because CLI server labels differ"
    )
    trafficEnabled = false
    local disabledReads = trafficReads
    tick(10)
    assert(trafficReads == disabledReads, "Disabled monitoring must not read traffic")
    trafficEnabled = true
    link = ""
    networkEvent("VPN disconnected")
    tick(3)
    assert(not serviceState.connected and calls["protonvpn info"] == 3)
    local reads = trafficReads
    tick(10)
    assert(trafficReads == reads, "Traffic reads must stop after disconnect")

    local before = calls["protonvpn info"]
    commandWatcher({ op = "refresh" })
    commandWatcher({ op = "refresh" })
    assert(calls["protonvpn info"] == before + 1, "In-flight refreshes must not overlap")
    drain()
    tick(1)
    assert(
        calls["protonvpn info"] == before + 2,
        "Refresh during an in-flight poll must not be lost"
    )
    commandWatcher({ op = "connect", target = "fastest" })
    drain()
    assert(calls["protonvpn info"] == before + 3, "Actions must refresh metadata")
    tick(600)
    assert(calls["protonvpn info"] == before + 3, "Actions must not restart periodic polling")
    commandWatcher({ op = "refresh_status" })
    drain()
    assert(calls["protonvpn info"] == before + 4, "Panel open must refresh metadata")
    print(
        "NoctaProton service: zero idle command launches over 20 simulated minutes, network events, live traffic, panel/actions and coalescing passed"
    )
end
