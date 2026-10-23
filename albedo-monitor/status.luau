--!nonstrict

local function activityColor(online, reliable, working, waiting)
    if not online then
        return "on_surface_variant"
    elseif not reliable or waiting > 0 then
        return "tertiary"
    elseif working > 0 then
        return "primary"
    end

    return "on_surface_variant"
end

local function activityText(online, reliable, working)
    if reliable then
        return tostring(working) .. " active"
    elseif online then
        return "status unavailable"
    end

    return "offline"
end

local function quotaColor(remaining)
    if remaining <= 10 then
        return "error"
    elseif remaining <= 30 then
        return "tertiary"
    end

    return "primary"
end

local function accountLabel(account)
    return account.provider .. " · " .. account.account
end

local function windowValue(account, window, online)
    if account.error ~= "" or (window.status ~= "" and window.status ~= "ok") then
        return "Unavailable", false
    end

    local remaining = window.remaining_percent
    if remaining == nil then
        return "Unknown", false
    end

    if not online or window.stale then
        return "Stale", false
    end

    return tostring(math.floor(remaining)) .. "% left", true
end

local function windowMeter(account, window, index, online, radius)
    local value, current = windowValue(account, window, online)
    local color = current and quotaColor(window.remaining_percent) or "on_surface_variant"
    local children = {}

    -- Never turn unknown or stale quota into an empty or full live meter.
    if current then
        children[#children + 1] = ui.progress({
            progress = window.remaining_percent / 100,
            width = 26,
            height = 4,
            radius = radius,
            fill = color,
            track = "on_surface/0.10",
        })
    end

    children[#children + 1] = ui.label({
        text = window.label .. " " .. value,
        fontSize = 11,
        color = color,
        maxLines = 1,
    })

    return ui.row({ key = "window-" .. tostring(index), align = "center", gap = 4 }, children)
end

local function accountSegment(account, index, title, online, radius)
    local children = {
        ui.label({
            text = title,
            fontSize = 11,
            fontWeight = "semibold",
            color = online and "on_surface" or "on_surface_variant",
            maxLines = 1,
        }),
    }

    for windowIndex, window in ipairs(account.windows) do
        children[#children + 1] = windowMeter(account, window, windowIndex, online, radius)
    end

    if #account.windows == 0 then
        children[#children + 1] = ui.label({
            text = "Quota unavailable",
            fontSize = 11,
            color = "on_surface_variant",
        })
    end

    return ui.row({ key = "account-" .. tostring(index), align = "center", gap = 5 }, children)
end

local function accountTooltip(account, online)
    local title = accountLabel(account)
    if account.id ~= "" then
        title = title .. " · " .. string.sub(account.id, 1, 12)
    end

    local lines = {}
    if account.error ~= "" then
        lines[#lines + 1] = account.error
    end
    if #account.windows == 0 then
        lines[#lines + 1] = "Quota unavailable"
    end

    for _, window in ipairs(account.windows) do
        local value = windowValue(account, window, online)
        if value == "Stale" and window.remaining_percent ~= nil then
            value = tostring(math.floor(window.remaining_percent)) .. "% left · stale"
        end
        lines[#lines + 1] = window.label .. ": " .. value
        if window.resets_at ~= "" then
            lines[#lines + 1] = "Resets " .. window.resets_at
        end
        if window.observed_at ~= "" then
            lines[#lines + 1] = "Observed " .. window.observed_at
        end
        if window.status ~= "" and window.status ~= "ok" then
            lines[#lines + 1] = window.status
        end
    end

    return { key = title, value = table.concat(lines, "\n") }
end

local function render()
    local data = noctalia.state.get("snapshot")
    local ready = type(data) == "table"
    local online = ready and data.online == true and data.stale ~= true
    local reliable = online and data.error == ""
    local working, waiting = 0, 0
    local tooltip = {}

    if online then
        for _, session in ipairs(data.sessions) do
            if session.status == "working" then
                working = working + 1
            end
            if session.status == "waiting" then
                waiting = waiting + 1
            end
        end

        local summary = "Incomplete snapshot · " .. data.error
        if reliable then
            summary = string.format(
                "%d working · %d waiting · %d sessions",
                working,
                waiting,
                #data.sessions
            )
        end
        tooltip[#tooltip + 1] = { key = "Albedo", value = summary }

        for index, session in ipairs(data.sessions) do
            if index > 8 then
                break
            end
            tooltip[#tooltip + 1] =
                { key = session.title, value = session.status .. " · " .. session.model }
        end
    else
        tooltip[#tooltip + 1] = {
            key = "Albedo",
            value = ready and data.error or "Waiting for daemon snapshot",
        }
    end

    local color = activityColor(online, reliable, working, waiting)
    local rows = {
        ui.glyph({ name = online and "robot" or "plug-off", size = 15, color = color }),
        ui.label({
            text = activityText(online, reliable, working),
            fontSize = 11,
            color = color,
            fontWeight = "semibold",
        }),
    }

    if reliable and waiting > 0 then
        rows[#rows + 1] =
            ui.label({ text = tostring(waiting) .. " waiting", fontSize = 11, color = "tertiary" })
    end

    local accounts = ready and data.accounts or {}
    local labelCounts = {}
    for _, account in ipairs(accounts) do
        local title = accountLabel(account)
        labelCounts[title] = (labelCounts[title] or 0) + 1
    end

    local scale = noctalia.getSetting("shell.corner_radius_scale")
    if type(scale) ~= "number" then
        scale = 1
    end

    -- Include every connected account, even when it has no usable quota windows.
    for index, account in ipairs(accounts) do
        local title = accountLabel(account)
        if labelCounts[title] > 1 then
            local identity = account.id ~= "" and string.sub(account.id, 1, 8) or tostring(index)
            title = title .. " · " .. identity
        end

        rows[#rows + 1] = ui.box({ width = 1, height = 14, fill = "outline/0.35" })
        rows[#rows + 1] = accountSegment(account, index, title, online, 2 * scale)
        tooltip[#tooltip + 1] = accountTooltip(account, online)
    end

    if online and #accounts == 0 then
        rows[#rows + 1] = ui.label({
            text = data.accounts_error ~= "" and "Account data unavailable"
                or "No connected accounts",
            fontSize = 11,
            color = "on_surface_variant",
        })
    end
    if ready and data.accounts_error ~= "" then
        tooltip[#tooltip + 1] = { key = "Accounts", value = data.accounts_error }
    end
    if ready and data.received_at ~= nil then
        tooltip[#tooltip + 1] = {
            key = "Snapshot",
            value = os.date("%H:%M:%S", data.received_at),
        }
    end

    barWidget.render(ui.row({ align = "center", gap = 6 }, rows))
    barWidget.setTooltip(tooltip)
end

noctalia.state.watch("snapshot", render)

function onClick()
    noctalia.togglePanel("adam0/albedo-monitor:panel")
end

function onRightClick()
    noctalia.state.set("command", { action = "refresh" })
end

render()
