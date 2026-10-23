--!nonstrict

local SESSION_COLORS = {
    working = "primary",
    waiting = "tertiary",
}

local opened = false

local function label(text, size, color)
    return ui.label({
        text = text,
        fontSize = size or 12,
        color = color or "on_surface",
        maxLines = 2,
    })
end

local function section(title, count)
    return ui.row({ justify = "space_between", align = "center", paddingV = 4 }, {
        ui.label({ text = title, fontSize = 13, color = "on_surface", fontWeight = "semibold" }),
        label(tostring(count), 11, "on_surface_variant"),
    })
end

local function sessionRow(session, scale)
    local color = SESSION_COLORS[session.status]
    local status = session.status
    local location = session.workspace
    if location == "" then
        location = "Unknown workspace"
    end

    local title = (session.parent_id ~= "" and "↳ " or "") .. session.title

    return ui.column({
        key = "session-" .. session.id,
        gap = 5,
        padding = 10,
        fill = "surface_variant/0.58",
        radius = 10 * scale,
        border = "outline",
        borderWidth = 1,
    }, {
        ui.row({ justify = "space_between", align = "center", gap = 8 }, {
            ui.label({
                text = title,
                fontSize = 12,
                fontWeight = "semibold",
                color = "on_surface",
                maxLines = 1,
                flexGrow = 1,
            }),
            label(status, 10, color),
        }),
        label(session.model .. " · " .. location, 10, "on_surface_variant"),
        label(
            string.sub(session.id, 1, 12)
                .. (session.phase ~= "" and (" · " .. session.phase) or ""),
            10,
            "on_surface_variant"
        ),
    })
end

-- Epochs come from the helper's timezone-aware datetime parser.
local function resetCountdown(epoch)
    if epoch == nil then
        return "Reset unavailable"
    end
    local seconds = epoch - os.time()
    if seconds <= 0 then
        return "Resetting now"
    end
    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    if days > 0 then
        return string.format("Resets in %dd %dh", days, hours)
    elseif hours > 0 then
        return string.format("Resets in %dh %dm", hours, minutes)
    end
    return string.format("Resets in %dm", math.max(1, minutes))
end

local function windowRow(window, stale, radius)
    local remaining = window.remaining_percent
    local old = stale
        or window.stale
        or (window.resets_at_epoch ~= nil and window.resets_at_epoch <= os.time())
    local color = "primary"
    if old then
        color = "on_surface_variant"
    elseif remaining ~= nil and remaining <= 10 then
        color = "error"
    end

    local value = remaining ~= nil and (tostring(math.floor(remaining)) .. "%") or "Unknown"
    if old then
        value = value .. " · stale"
    end

    local rows = {
        ui.row({ justify = "space_between", gap = 8 }, {
            label(window.label, 11, "on_surface_variant"),
            label(value, 11, color),
        }),
    }

    if remaining ~= nil then
        rows[#rows + 1] = ui.progress({
            progress = remaining / 100,
            fill = color,
            track = "on_surface/0.10",
            height = 4,
            radius = radius,
        })
    end

    if window.resets_at_epoch ~= nil or window.resets_at ~= "" then
        rows[#rows + 1] = label(resetCountdown(window.resets_at_epoch), 10, "on_surface_variant")
    end
    if window.status ~= "" and window.status ~= "ok" then
        rows[#rows + 1] = label(window.status, 10, "on_surface_variant")
    end

    return ui.column({ gap = 4, paddingV = 4 }, rows)
end

local function accountRow(account, index, stale, scale)
    local children = {
        ui.label({
            text = account.provider,
            fontSize = 12,
            fontWeight = "semibold",
            color = "on_surface",
            maxLines = 1,
        }),
        label(
            account.account
                .. (account.id ~= "" and (" · " .. string.sub(account.id, 1, 12)) or ""),
            10,
            "on_surface_variant"
        ),
    }

    if account.error ~= "" then
        children[#children + 1] = label(account.error, 11, "tertiary")
    end
    if #account.windows == 0 then
        children[#children + 1] = label("Quota unavailable", 11, "on_surface_variant")
    end

    for index, window in ipairs(account.windows) do
        if index > 20 then
            children[#children + 1] =
                label(tostring(#account.windows - 20) .. " more limits", 10, "on_surface_variant")
            break
        end
        children[#children + 1] = windowRow(window, stale or account.error ~= "", 2 * scale)
    end

    return ui.column({
        key = "account-" .. tostring(index),
        gap = 8,
        padding = 12,
        fill = "surface_variant/0.58",
        radius = 12 * scale,
        border = "outline",
        borderWidth = 1,
    }, children)
end

local function render()
    if not opened then
        return
    end

    local data = noctalia.state.get("snapshot")
    local ready = type(data) == "table"
    local online = ready and data.online and not data.stale
    local stale = not online
    local status = "CONNECTING"

    if online then
        status = data.error ~= "" and "PARTIAL SNAPSHOT" or "DAEMON ONLINE"
    elseif ready then
        status = "OFFLINE"
    end

    local content = {}
    local sessions = {}
    if online then
        for _, session in ipairs(data.sessions) do
            if session.status == "working" or session.status == "waiting" then
                sessions[#sessions + 1] = session
            end
        end
    end
    local accounts = ready and data.accounts or {}
    local scale = noctalia.getSetting("shell.corner_radius_scale")
    if type(scale) ~= "number" then
        scale = 1
    end

    if ready and data.error ~= "" then
        content[#content + 1] = label(
            data.error .. (data.stale and " · showing last known data" or ""),
            12,
            "tertiary"
        )
    end

    content[#content + 1] = section("Active sessions & agents", #sessions)
    if #sessions == 0 then
        local message = "Daemon unavailable"
        if online then
            message = data.error == "" and "No active sessions" or "Session status unavailable"
        end
        content[#content + 1] = label(message, 12, "on_surface_variant")
    end

    -- Bound the UI tree without hiding how much data remains outside the panel.
    for index, session in ipairs(sessions) do
        if index > 60 then
            content[#content + 1] =
                label(tostring(#sessions - 60) .. " more active sessions", 11, "on_surface_variant")
            break
        end
        content[#content + 1] = sessionRow(session, scale)
    end

    content[#content + 1] = ui.separator({ color = "outline", opacity = 0.2, spacing = 4 })
    content[#content + 1] = section("Accounts", #accounts)
    if ready and data.accounts_error ~= "" then
        content[#content + 1] = label(data.accounts_error, 11, "tertiary")
    end
    if #accounts == 0 then
        content[#content + 1] = label(
            online and "No account quota available" or "Account data unavailable",
            12,
            "on_surface_variant"
        )
    end

    for index, account in ipairs(accounts) do
        if index > 40 then
            content[#content + 1] =
                label(tostring(#accounts - 40) .. " more accounts", 11, "on_surface_variant")
            break
        end
        content[#content + 1] = accountRow(account, index, stale, scale)
    end

    local refreshed = "Waiting for snapshot"
    if ready and data.received_at ~= nil then
        refreshed = "Snapshot " .. os.date("%H:%M:%S", data.received_at)
    end

    panel.render(ui.column({ flexGrow = 1, padding = 16, gap = 8 }, {
        ui.row({ justify = "space_between", align = "center" }, {
            ui.row({ gap = 8, align = "center" }, {
                ui.glyph({ name = "robot", size = 20, color = "primary" }),
                ui.label({
                    text = "Albedo",
                    fontSize = 18,
                    fontWeight = "bold",
                    color = "on_surface",
                }),
            }),
            ui.row({ gap = 6 }, {
                ui.button({
                    glyph = "refresh",
                    variant = "outline",
                    controlSize = "sm",
                    tooltip = "Read daemon snapshot",
                    onClick = "onRefresh",
                }),
                ui.button({
                    glyph = "x",
                    variant = "outline",
                    controlSize = "sm",
                    tooltip = "Close",
                    onClick = "onCloseClicked",
                }),
            }),
        }),
        ui.row({ justify = "space_between", gap = 8 }, {
            label(status, 10, online and "primary" or "on_surface_variant"),
            label(refreshed, 10, "on_surface_variant"),
        }),
        ui.scroll({ key = "albedo-content", flexGrow = 1, gap = 8 }, content),
    }))
end

noctalia.state.watch("snapshot", render)

function onOpen(_context)
    opened = true
    render()
    noctalia.state.set("command", { action = "refresh" })
end

function onClose()
    opened = false
end

function onCloseClicked()
    panel.close()
end

function onRefresh()
    noctalia.state.set("command", { action = "refresh" })
end
