--!nonstrict

local opened = false
local activeTab = "active"
local STATUS = {
    downloading = "Downloading",
    paused = "Paused",
    queued = "Queued",
    completed = "Completed",
    error = "Failed",
}

local function label(text, size, color)
    return ui.label({
        text = text,
        fontSize = size or 12,
        color = color or "on_surface",
        maxLines = 2,
    })
end

local function bytes(value)
    local units = { "B", "KiB", "MiB", "GiB", "TiB" }
    local index = 1
    while value >= 1024 and index < #units do
        value = value / 1024
        index = index + 1
    end
    return string.format("%.1f %s", value, units[index])
end

local function eta(item)
    if item.total <= 0 or item.speed <= 0 then
        return "ETA —"
    end
    local seconds = math.ceil(math.max(0, item.total - item.downloaded) / item.speed)
    if seconds < 60 then
        return tostring(seconds) .. "s left"
    elseif seconds < 3600 then
        return tostring(math.ceil(seconds / 60)) .. "m left"
    elseif seconds < 86400 then
        return string.format("%.1fh left", seconds / 3600)
    end
    return string.format("%.1fd left", seconds / 86400)
end

local function panelBorder()
    local enabled = noctalia.getSetting("shell.panel.borders")
    local width = noctalia.getSetting("shell.panel.border_width")
    local color = noctalia.getSetting("shell.panel.border_color")
    if type(width) ~= "number" or width ~= width or math.abs(width) == math.huge then
        width = 1
    end
    if type(color) ~= "string" or color == "" then
        color = "outline"
    end
    return { width = enabled == false and 0 or math.clamp(width, 0, 20), color = color }
end

local function card(key, children, scale, border)
    return ui.column({
        key = key,
        gap = 10,
        padding = 12,
        fill = "surface_variant/0.58",
        radius = 12 * scale,
        border = border.color,
        borderWidth = border.width,
    }, children)
end

local function speedCard(data, items, scale, border)
    local speed, peak, sum = 0, 0, 0
    local history = data.speedHistory or {}
    for _, item in ipairs(items) do
        speed = speed + item.speed
    end
    for _, sample in ipairs(history) do
        peak = math.max(peak, sample)
        sum = sum + sample
    end
    local values = {}
    for _, sample in ipairs(history) do
        values[#values + 1] = peak > 0 and sample / peak or 0
    end
    -- A lone observation is not yet a trend.
    local chart = #values >= 2
            and ui.graph({
                key = "speed-history",
                height = 76,
                values = values,
                color = "primary",
                lineWidth = 2,
                fillOpacity = 0.14,
            })
        or label("Collecting speed history…", 12, "on_surface_variant")
    return card("speed-card", {
        ui.row({ justify = "space_between", align = "center", gap = 8 }, {
            label("Download speed", 12, "on_surface_variant"),
            label(tostring(#items) .. " active", 12, "primary"),
        }),
        label(bytes(speed) .. "/s", 26, "primary"),
        chart,
        ui.row({ justify = "space_between", gap = 8 }, {
            label("Peak " .. bytes(peak) .. "/s", 11, "on_surface_variant"),
            label(
                "Avg " .. bytes(#history > 0 and sum / #history or 0) .. "/s",
                11,
                "on_surface_variant"
            ),
        }),
        label(
            "Latest " .. tostring(#history) .. " polls · scale 0–" .. bytes(peak) .. "/s",
            11,
            "on_surface_variant"
        ),
    }, scale, border)
end

local function downloadCard(item, index, scale, border)
    local children = {
        label(item.filename, 14),
        label(
            STATUS[item.status] or "Download",
            11,
            item.status == "error" and "error" or "on_surface_variant"
        ),
        ui.row({ justify = "space_between", gap = 8 }, {
            label(
                item.progress ~= nil and string.format("%d%%", math.floor(item.progress * 100))
                    or "Size unknown",
                12,
                "primary"
            ),
            label(item.status == "downloading" and (bytes(item.speed) .. "/s") or "", 12),
        }),
    }
    if item.progress ~= nil and item.status ~= "completed" and item.status ~= "error" then
        children[#children + 1] = ui.progress({
            progress = item.progress,
            height = 5,
            radius = 2.5 * scale,
            fill = "primary",
            track = "on_surface/0.10",
        })
    end
    children[#children + 1] = ui.row({ justify = "space_between", gap = 8 }, {
        label(
            bytes(item.downloaded) .. " / " .. (item.total > 0 and bytes(item.total) or "unknown"),
            11,
            "on_surface_variant"
        ),
        label(item.status == "downloading" and eta(item) or "", 11, "on_surface_variant"),
    })
    return card("download-" .. tostring(index) .. "-" .. item.id, children, scale, border)
end

local function render()
    if not opened then
        return
    end
    local data = noctalia.state.get("downloads") or { items = {}, error = "" }
    local items = data.items or {}
    local active, history = data.active or {}, data.history or {}
    local selected = activeTab == "active" and active or history
    local scale = noctalia.getSetting("shell.corner_radius_scale")
    if type(scale) ~= "number" or scale ~= scale or math.abs(scale) == math.huge then
        scale = 1
    end
    scale = math.max(0, scale)
    local border = panelBorder()
    local rows = {}
    for index, item in ipairs(selected) do
        if index > 40 then
            rows[#rows + 1] = label(
                tostring(#selected - 40)
                    .. (
                        activeTab == "active" and " more active downloads"
                        or " more history entries"
                    ),
                12,
                "on_surface_variant"
            )
            break
        end
        rows[#rows + 1] = downloadCard(item, index, scale, border)
    end
    if #rows == 0 then
        rows[1] = card("empty", {
            label(activeTab == "active" and "No active downloads" or "No download history", 14),
            label(
                activeTab == "active" and "Downloading, queued, and paused files appear here."
                    or "Completed and failed downloads appear here.",
                12,
                "on_surface_variant"
            ),
        }, scale, border)
    end
    local content = { speedCard(data, items, scale, border) }
    if data.error ~= "" then
        content[#content + 1] = card("connection-error", {
            label("Server unavailable", 14),
            label(
                data.error .. (#history > 0 and " · Showing last known history" or ""),
                12,
                "on_surface_variant"
            ),
        }, scale, border)
    end
    for _, row in ipairs(rows) do
        content[#content + 1] = row
    end
    panel.render(ui.column({ flexGrow = 1, padding = 16, gap = 12 }, {
        ui.row({ justify = "space_between", align = "center" }, {
            label("Surge", 18),
            ui.row({ key = "panel-actions", align = "center", gap = 6 }, {
                ui.button({
                    glyph = "refresh",
                    controlSize = "sm",
                    tooltip = "Refresh",
                    onClick = function()
                        noctalia.state.set("command", { action = "refresh" })
                    end,
                }),
                ui.button({
                    glyph = "x",
                    controlSize = "sm",
                    tooltip = "Close",
                    onClick = function()
                        panel.close()
                    end,
                }),
            }),
        }),
        ui.row({ gap = 8 }, {
            ui.button({
                key = "tab-active",
                text = "Active · " .. tostring(#active),
                selected = activeTab == "active",
                variant = "ghost",
                flexGrow = 1,
                onClick = function()
                    activeTab = "active"
                    render()
                end,
            }),
            ui.button({
                key = "tab-history",
                text = "History · " .. tostring(#history),
                selected = activeTab == "history",
                variant = "ghost",
                flexGrow = 1,
                onClick = function()
                    activeTab = "history"
                    render()
                end,
            }),
        }),
        ui.scroll({ key = "surge-" .. activeTab, flexGrow = 1, gap = 10 }, content),
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
