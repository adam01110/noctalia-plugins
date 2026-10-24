--!nonstrict
local settingScale = 1
local config = { text_size = "normal", show_add_zone = true }
local zones = { { id = "Europe/Paris", time = "12:00", offset = "UTC+1" } }
local stateValues = {}
local lastPanel, command
local noctalia = {
  getSetting = function(key) if key == "shell.corner_radius_scale" then return settingScale end end,
  getConfig = function(key) return config[key] end,
  tr = function(key) return key end,
  string = { trim = function(value) return value:match("^%s*(.-)%s*$") end },
  state = {
    get = function(key) if key == "world_clock.zones" then return zones end end,
    set = function(key, value) stateValues[key] = value; command = value end,
    watch = function() end,
  },
}
local ui = setmetatable({}, { __index = function(_, kind)
  return function(props, children) return { kind = kind, props = props or {}, children = children or {} } end
end })
local panel = { render = function(node) lastPanel = node end, close = function() end, setWantsSecondTicks = function() end }
local function loadPanel()
  -- PANEL_SOURCE
end
loadPanel()
assert(type(onOpen) == "function", "Panel must expose onOpen")
onOpen({})
local function walk(node, visit)
  visit(node)
  for _, child in ipairs(node.children or {}) do if child then walk(child, visit) end end
end
local function find(node, kind, predicate)
  local found
  walk(node, function(candidate) if not found and candidate.kind == kind and predicate(candidate.props) then found = candidate end end)
  return found
end
local row = assert(find(lastPanel, "row", function(props) return props.key == "zone-Europe/Paris" end))
assert(row.props.border == "outline" and row.props.borderWidth == 1, "reorderable zone row needs outline")
assert(row.props.radius == 6, "default zone radius")
local add = assert(find(lastPanel, "button", function(props) return props.glyph == "plus" end))
local input = assert(find(lastPanel, "input", function(props) return props.key:match("^add%-") end))
assert(add.props.controlSize == "md" and input.props.controlSize == add.props.controlSize, "Add and input must share native control height")
settingScale = 0
onOpen({})
row = assert(find(lastPanel, "row", function(props) return props.key == "zone-Europe/Paris" end))
assert(row.props.radius == 0, "zero shell radius scale must be honored")
local gap = assert(find(lastPanel, "dropZone", function(props) return props.key == "gap-1" end))
assert(gap.props.radius == 0, "drop target radius must scale to zero")
for _, case in ipairs({
  { value = 0.5, radius = 3 },
  { value = 1.5, radius = 9 },
  { value = "invalid", radius = 6 },
  { value = -1, radius = 0 },
  { value = 0 / 0, radius = 6 },
  { value = math.huge, radius = 6 },
}) do
  settingScale = case.value
  onOpen({})
  row = assert(find(lastPanel, "row", function(props) return props.key == "zone-Europe/Paris" end))
  assert(row.props.radius == case.radius, "Custom cards must follow shell radius settings")
  assert(row.props.border == "outline" and row.props.borderWidth == 1)
end
local grip = assert(find(lastPanel, "dragSource", function(props) return props.payload == "Europe/Paris" end))
assert(grip.props.dragType == "world-clock-zone" and grip.props.liftFromLayout)
onZoneDropped("Europe/Paris", "2")
assert(command.op == "reorder" and command.zone == "Europe/Paris" and command.index == 2)
local previous = command
onZoneDropped("", "invalid")
assert(command == previous, "Malformed drops must not dispatch commands")
input = assert(find(lastPanel, "input", function(props) return props.key:match("^add%-") end))
input.props.onChange("  Europe/Berlin  ")
onAdd()
assert(command.op == "add" and command.zone == "Europe/Berlin")
local edit = assert(find(lastPanel, "button", function(props) return props.glyph == "pencil" end))
edit.props.onClick()
local labelInput = assert(find(lastPanel, "input", function(props) return props.key:match("^label%-") end))
labelInput.props.onChange("Paris")
onLabelSubmit()
assert(command.op == "label" and command.zone == "Europe/Paris" and command.label == "Paris")
local trash = assert(find(lastPanel, "button", function(props) return props.glyph == "trash" end))
trash.props.onClick()
local confirm = assert(find(lastPanel, "button", function(props) return props.variant == "destructive" end))
confirm.props.onClick()
assert(command.op == "remove" and command.zone == "Europe/Paris")
config.show_add_zone = false
onOpen({})
assert(not find(lastPanel, "button", function(props) return props.glyph == "plus" end), "hidden add setting")
print("World Clock: card outlines, square/scaled/invalid radii, matched input/Add heights and zone commands passed")
