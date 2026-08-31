--!nonstrict

-- Helpers
local function tr(key)
	return noctalia.tr(key)
end

local function cfg(key)
	return noctalia.getConfig(key)
end

local function getState(key)
	return noctalia.state.get(key)
end

local function setState(key, value)
	noctalia.state.set(key, value)
end

local function watchState(key, cb)
	noctalia.state.watch(key, cb)
end

local function getBackgroundColor()
	local color = cfg("panel_card_color")
	local opacity = cfg("panel_card_opacity") / 100
	return `{color}/{opacity}`
end

-- Scales the card radius by the shell-wide corner_radius_scale
-- (0 = square, 1 = default, 2 = extra rounded) so the panel respects the
-- user's corner-roundness setting instead of hardcoding a rounded value.
local function cornerRadius()
	local scale = noctalia.getSetting("shell.corner_radius_scale")
	if type(scale) ~= "number" then
		scale = 1
	end
	return 8 * scale
end

local function statLabel(text, glyph)
	local items = {}
	if glyph ~= nil then
		table.insert(
			items,
			ui.glyph({
				name = glyph,
				size = 16,
			})
		)
	end

	table.insert(
		items,
		ui.label({
			text = text,
			fontSize = 12,
			fontWeight = "semibold",
		})
	)

	return ui.row({
		gap = 8,
		align = "center",
	}, items)
end

local function render()
	local buttons = {
		ui.button({
			text = tr("panel.refresh"),
			glyph = "refresh",
			flexGrow = 1,
			variant = "outline",
			onClick = "onRefreshClicked",
		}),
	}

	if not cfg("hide_optimize_button") then
		table.insert(
			buttons,
			ui.button({
				text = tr("panel.optimize"),
				glyph = "database-cog",
				flexGrow = 1,
				variant = "primary",
				onClick = "onOptimizeClicked",
			})
		)
	end

	if not cfg("hide_clean_button") then
		table.insert(
			buttons,
			ui.button({
				text = tr("panel.clean"),
				glyph = "trash",
				flexGrow = 1,
				variant = "destructive",
				onClick = "onCleanClicked",
			})
		)
	end

	local generationItems = {
		statLabel(`SYS: {getState("nixosGenerations")}`, "device-desktop"),
		statLabel(`{tr("panel.current")}: {getState("nixosCurrentGen")}`, "device-desktop-check"),
	}

	if getState("hasHomeManager") and getState("hmGenerations") ~= "" and getState("hmCurrentGen") ~= "" then
		table.insert(generationItems, statLabel(`HM: {getState("hmGenerations")}`, "home"))
		table.insert(generationItems, statLabel(`{tr("panel.current")}: {getState("hmCurrentGen")}`, "home-check"))
	end

	panel.render(ui.column({
		gap = 8,
	}, {
		ui.label({
			text = tr("panel.title"),
			fontSize = 16,
		}),
		ui.separator({
			thickness = 2,
			orientation = "horizontal",
			spacing = 4,
		}),
		ui.row({
			fill = getBackgroundColor(),
			align = "center",
			justify = "space_between",
			flexGrow = 1,
			paddingV = 4,
			paddingH = 8,
			radius = cornerRadius(),
		}, generationItems),
		ui.row({
			fill = getBackgroundColor(),
			align = "center",
			justify = "center",
			flexGrow = 1,
			paddingV = 4,
			paddingH = 8,
			radius = cornerRadius(),
		}, {
			statLabel(`{tr("panel.store_size")}: {getState("storeSize")}`, "database"),
			ui.spacer({ width = 16 }),
			statLabel(`{tr("panel.closure_size")}: {getState("closureSize")}`, "server"),
		}),
		ui.separator({
			thickness = 2,
			orientation = "horizontal",
			spacing = 4,
		}),
		ui.row({
			gap = 8,
			align = "center",
			justify = "space_between",
		}, buttons),
	}))
end

-- State watcher
watchState("storeSize", render)
watchState("closureSize", render)
watchState("nixosGenerations", render)
watchState("nixosCurrentGen", render)
watchState("hmGenerations", render)
watchState("hmCurrentGen", render)
watchState("hasHomeManager", render)

-- Hooks
function onOpen(_ctx)
	render()
end

function update()
	render()
end

-- Click handlers
function onRefreshClicked()
	setState("command", "refresh")
end

function onOptimizeClicked()
	local command = cfg("optimize_command")
	if command == "" then
		noctalia.notifyError(tr("notification.optimize_command_is_empty"))
		return
	end
	runCommandInTerminal(command)
end

function onCleanClicked()
	local command = cfg("clean_command")
	if command == "" then
		noctalia.notifyError(tr("notification.clean_command_is_empty"))
		return
	end
	runCommandInTerminal(command)
end

function runCommandInTerminal(command)
	if cfg("close_on_enter") then
		command = `{command} && echo && read -p "{tr("terminal.press_enter_to_exit")}"`
	end

	command = `{command} || (echo && read -p "{tr("terminal.command_exits_non_zero")}")`
	panel.close()
	noctalia.runInTerminal(command)
end
