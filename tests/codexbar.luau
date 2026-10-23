--!nonstrict
local state = {}
local watchers = {}
local selectedPanel
local pending
local lastTree
local noctalia = {
    getConfig = function(key)
        return ({ codexbarPath = "codexbar", refreshIntervalSec = 60, barProviderLimit = 2 })[key]
    end,
    getSetting = function() return 0 end,
    state = {
        get = function(key) return state[key] end,
        set = function(key, value)
            state[key] = value
            if watchers[key] then watchers[key](value) end
        end,
        watch = function(key, fn) watchers[key] = fn end,
    },
    setUpdateInterval = function() end,
    runAsync = function(_, callback) pending = callback; return true end,
    togglePanel = function(id) selectedPanel = id end,
    json = { decode = function(value) return value end },
}
local ui = setmetatable({}, { __index = function(_, kind)
    return function(props, children) return { kind = kind, props = props, children = children } end
end })
local barWidget = {
    render = function(tree) lastTree = tree end,
    setTooltip = function() end,
}

do
-- PLUGIN_SOURCE
end

local function expectPanel(providers, tier)
    noctalia.state.set("providers", providers)
    onClick()
    assert(selectedPanel == "salemsayed/codexbar-meter:" .. tier, selectedPanel)
end
expectPanel({}, "panel-compact")
expectPanel({ { provider = "codex", usage = { primary = { usedPercent = 30 } } } }, "panel-compact")
local provider = { provider = "codex", usage = { primary = { usedPercent = 30 }, secondary = { usedPercent = 40 }, tertiary = { usedPercent = 50 } } }
expectPanel({ provider }, "panel")
expectPanel({ provider, provider }, "panel-tall")
pending({ exitCode = 1, stdout = nil })
onClick()
assert(selectedPanel == "salemsayed/codexbar-meter:panel-tall", "refresh failure must retain existing providers")
assert(lastTree ~= nil)
print("CodexBar panel tiers and refresh failure: passed")
