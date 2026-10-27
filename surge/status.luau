--!nonstrict

local function render()
    local data = noctalia.state.get("downloads")
    local items = type(data) == "table" and data.items or {}
    barWidget.setVisible(true)
    if #items == 0 then
        barWidget.render(ui.row({ align = "center", gap = 6 }, {
            ui.glyph({ name = "download", size = 15, color = "on_surface_variant" }),
        }))
        barWidget.setTooltip(
            type(data) == "table" and data.error ~= "" and data.error or "No active downloads"
        )
        return
    end

    local total, downloaded = 0, 0
    local known = true
    local tooltip = {}
    for index, item in ipairs(items) do
        total = total + item.total
        downloaded = downloaded + math.min(item.downloaded, item.total)
        known = known and item.progress ~= nil
        if index <= 8 then
            tooltip[#tooltip + 1] = {
                key = item.filename,
                value = item.progress ~= nil
                        and string.format("%d%%", math.floor(item.progress * 100))
                    or "Downloading · size unknown",
            }
        end
    end
    local scale = noctalia.getSetting("shell.corner_radius_scale")
    if type(scale) ~= "number" then
        scale = 1
    end
    local children = {
        ui.glyph({ name = "download", size = 15, color = "primary" }),
        ui.label({
            text = tostring(#items),
            fontSize = 12,
            color = "primary",
            fontWeight = "semibold",
        }),
        ui.box({ width = 1, height = 14, fill = "outline/0.35" }),
    }
    -- Match Albedo Monitor's 26×4 meter, typography, and spacing.
    if known then
        children[#children + 1] = ui.progress({
            progress = downloaded / total,
            width = 26,
            height = 4,
            radius = 2 * scale,
            fill = "primary",
            track = "on_surface/0.10",
        })
    end
    children[#children + 1] = ui.label({
        text = known and (tostring(math.floor(downloaded / total * 100)) .. "%") or "—",
        fontSize = 12,
        color = "primary",
        maxLines = 1,
    })
    barWidget.render(ui.row({ align = "center", gap = 6 }, children))
    barWidget.setTooltip(tooltip)
end

noctalia.state.watch("downloads", render)

function onClick()
    noctalia.togglePanel("adam0/surge:panel")
end

function onRightClick()
    noctalia.state.set("command", { action = "refresh" })
end

render()
