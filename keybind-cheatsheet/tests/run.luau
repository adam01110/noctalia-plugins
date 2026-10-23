--!nonstrict
local host = require("./host_mock")
local fixtureFiles = require("./fixture_data")
local files = {}
local translations = fixtureFiles.translations
fixtureFiles.translations = nil
host.noctalia.tr = function(key, values)
    local text = translations[key] or key
    for name, value in pairs(values or {}) do text = text:gsub("{" .. name .. "}", tostring(value)) end
    return text
end
for path, value in pairs(fixtureFiles) do
    files[path] = type(value) == "table" and host.noctalia.json.encode(value) or value
end
host.setFiles(files)
host.queueEvents()
local service = require("../service")
service.runSelfTest()
host.flushEvents()
local report = host.noctalia.json.decode(host.fileContent("/data/selftest.json"))
assert(report and report.passed, "upstream parser fixtures failed")
local cases = 0
for name, case in pairs(report.cases) do
    assert(case.passed, name)
    cases += 1
end
assert(cases == 5)
print("Parser fixtures: 5 passed (Mango, Hyprland conf/Lua, Niri, Fcitx5)")

host.resetRuntime()
host.setConfig({ compositor = "niri", niri_config = "/config.kdl" })
local lines = { "binds {" }
for i = 1, 180 do
    table.insert(lines, 'Mod+F' .. i .. ' { spawn "app' .. i .. '"; }')
end
table.insert(lines, "}")
host.setFile("/config.kdl", table.concat(lines, "\n"))
service.resetForTests()
assert(host.flushEvents() > 1, "Niri parsing must span separate events")
assert(service.lifecycleState().bindingCount == 180)
assert(not service.lifecycleState().refreshing)
assert(host.updateInterval() == nil, "refresh must remain event-driven")
host.setFileExists("/config.kdl", false)
service.refresh()
host.flushEvents()
assert(service.lifecycleState().bindingCount == 180, "failed refresh must preserve last-good data")
print("Staged Niri refresh and last-good recovery: passed")

local viewer = require("../panel")
assert(viewer.formatKey("XF86AudioRaiseVolume") == "Vol Up")
assert(viewer.formatKey("mouse:272") == "LMB")
assert(viewer.formatKey("Page_Up") == "PgUp")
viewer.onOpen()
assert(host.flushEvents() > 1, "panel fill must span separate events")
assert(viewer.lifecycleState().bindingCount == 180)
assert(host.renderCount() > 1, "large keymaps must render progressively")
assert(host.renderedTree() ~= nil)
viewer.onClose()
assert(not viewer.lifecycleState().panelOpen)
print("Key labels, progressive panel open/close: passed")
