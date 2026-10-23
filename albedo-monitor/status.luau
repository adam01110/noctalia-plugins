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

local function render()
    local data = noctalia.state.get("snapshot")
    local online = type(data) == "table" and data.online == true and data.stale ~= true
    local reliable = online and data.error == ""
    local working, waiting = 0, 0
    local minimum = nil
    local quotaLabel = ""
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

        -- Only fresh windows from healthy accounts participate in the bar minimum.
        for _, account in ipairs(data.accounts) do
            if account.error == "" then
                for _, window in ipairs(account.windows) do
                    local remaining = window.remaining_percent
                    if
                        remaining ~= nil
                        and not window.stale
                        and (minimum == nil or remaining < minimum)
                    then
                        minimum = remaining
                        quotaLabel = account.provider
                            .. " · "
                            .. account.account
                            .. " · "
                            .. window.label
                    end
                end
            end
        end

        if minimum ~= nil then
            tooltip[#tooltip + 1] = {
                key = "Lowest remaining",
                value = quotaLabel .. ": " .. tostring(math.floor(minimum)) .. "% left",
            }
        else
            tooltip[#tooltip + 1] = { key = "Quota", value = "No current quota available" }
        end
        if data.accounts_error ~= "" then
            tooltip[#tooltip + 1] = { key = "Accounts", value = data.accounts_error }
        end
    else
        tooltip[#tooltip + 1] = {
            key = "Albedo",
            value = type(data) == "table" and data.error or "Waiting for daemon snapshot",
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

    if online and minimum ~= nil then
        local quotaColor = "on_surface_variant"
        if minimum <= 10 then
            quotaColor = "error"
        elseif minimum <= 30 then
            quotaColor = "tertiary"
        end

        rows[#rows + 1] = ui.label({
            text = tostring(math.floor(minimum)) .. "% left",
            fontSize = 11,
            color = quotaColor,
        })
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
