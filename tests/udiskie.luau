--!nonstrict

local lastPanel, toggled, command
local settingsOpened = false
local noctalia = {
    getSetting = function() return 1 end,
    getConfig = function() return nil end,
    tr = function(key) return key end,
    state = {
        get = function() return nil end,
        watch = function() end,
    },
    openSettings = function() settingsOpened = true end,
    togglePanel = function(id) toggled = id end,
    runAsync = function(value) command = value end,
}
local ui = setmetatable({}, {
    __index = function(_, kind)
        return function(props, children)
            return { kind = kind, props = props or {}, children = children or {} }
        end
    end,
})
local panel = { render = function(node) lastPanel = node end }
local barWidget = setmetatable({}, { __index = function() return function() end end })

local function loadPanel()
    -- PANEL_SOURCE
end
loadPanel()

local function findButton(node, glyph)
    if node.kind == "button" and node.props.glyph == glyph then return node.props end
    for _, child in ipairs(node.children) do
        local result = findButton(child, glyph)
        if result then return result end
    end
    return nil
end

local settings = assert(findButton(lastPanel, "settings"))
assert(settings.variant == nil, "Settings uses the native button surface")
settings.onClick()
assert(settingsOpened, "Settings must still open the plugin settings")
findButton(lastPanel, "link").onClick()
assert(command == "noctalia msg plugin adam0/udiskie:service all mount_all")
findButton(lastPanel, "unlink").onClick()
assert(command == "noctalia msg plugin adam0/udiskie:service all unmount_all")

local function loadStatus()
    -- STATUS_SOURCE
    onClick()
    assert(toggled == "adam0/udiskie:manager")
    onRightClick()
    assert(command == "noctalia msg plugin adam0/udiskie:service all refresh")
end
loadStatus()
print("Udiskie: native Settings surface, Settings action, custom panel and service targets passed")
