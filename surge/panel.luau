--!nonstrict

local opened = false

local function label(text, size, color)
    return ui.label({
        text = text,
        fontSize = size or 12,
        color = color or "on_surface",
        maxLines = 2,
    })
end

local function rate(bytes)
    local units = { "B/s", "KiB/s", "MiB/s", "GiB/s" }
    local index = 1
    while bytes >= 1024 and index < #units do
        bytes = bytes / 1024
        index = index + 1
    end
    return string.format("%.1f %s", bytes, units[index])
end

local function render()
    if not opened then
        return
    end
    local data = noctalia.state.get("downloads")
    local items = type(data) == "table" and data.items or {}
    local rows = {}
    local scale = noctalia.getSetting("shell.corner_radius_scale")
    if type(scale) ~= "number" then
        scale = 1
    end
    for index, item in ipairs(items) do
        if index > 40 then
            rows[#rows + 1] =
                label(tostring(#items - 40) .. " more active downloads", 12, "on_surface_variant")
            break
        end
        local children = {
            label(item.filename, 14),
            ui.row({ justify = "space_between", gap = 8 }, {
                label(
                    item.progress ~= nil and string.format("%d%%", math.floor(item.progress * 100))
                        or "Size unknown",
                    12,
                    "on_surface_variant"
                ),
                label(rate(item.speed), 12, "on_surface_variant"),
            }),
        }
        if item.progress ~= nil then
            children[#children + 1] = ui.progress({
                progress = item.progress,
                height = 4,
                radius = 2 * scale,
                fill = "primary",
                track = "on_surface/0.10",
            })
        end
        rows[#rows + 1] =
            ui.column({ key = "download-" .. tostring(index), gap = 6, paddingV = 10 }, children)
    end
    if #rows == 0 then
        rows[1] = label(
            type(data) == "table" and data.error ~= "" and data.error or "No active downloads",
            12,
            "on_surface_variant"
        )
    end
    panel.render(ui.column({ flexGrow = 1, padding = 16, gap = 12 }, {
        ui.row({ justify = "space_between", align = "center" }, {
            label("Surge · " .. tostring(#items) .. " downloading", 14),
            ui.button({
                glyph = "refresh",
                controlSize = "sm",
                tooltip = "Refresh",
                onClick = function()
                    noctalia.state.set("command", { action = "refresh" })
                end,
            }),
        }),
        ui.scroll({ key = "surge-downloads", flexGrow = 1, gap = 4 }, rows),
    }))
end

noctalia.state.watch("downloads", render)

function onOpen()
    opened = true
    render()
end

function onClose()
    opened = false
end
