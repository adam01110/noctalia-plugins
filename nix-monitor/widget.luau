--!nonstrict

local function cfg(key)
	return noctalia.getConfig(key)
end

local function render()
	local children = {
		ui.glyph({
			name = cfg("glyph"),
			size = 16,
			width = 20,
			height = 20,
		}),
	}
	if cfg("show_text") then
		table.insert(children, ui.label({ text = cfg("text") }))
	end
	barWidget.render(ui.row({ align = "center", gap = 4 }, children))
end

function onClick()
	noctalia.togglePanel("avivbintangaringga/nix-monitor:panel")
end

render()
