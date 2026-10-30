--!nonstrict
local GitLab = require("./lib/gitlab.luau")
local Activity = require("./lib/activity.luau")
-- Native work queue: forge -> repository scope -> bounded, readable rows.
local opened = false
local snapshot = noctalia.state.get("forges.snapshot")
    or { provider = "tangled", status = "loading" }
local tab = snapshot.view == "overview" and "repositories" or (snapshot.view or "repositories")
local notificationFilter = "all"
local inboxPage = 1
local INBOX_PAGE_SIZE = 20
local query, repositoryDraft, inputError = "", "", ""
local render
local commandSequence, filterRevision = 0, 0
local function send(value)
    commandSequence += 1
    value.nonce = tostring(noctalia.nowMs()) .. "-" .. tostring(commandSequence)
    noctalia.state.set("forges.command", value)
end
local function label(text, size, color)
    return ui.label({
        text = text,
        fontSize = size or 12,
        color = color or "on_surface_variant",
        maxLines = 2,
    })
end
local function finite(value, fallback)
    if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
        return fallback
    end
    return value
end
local function surface(key)
    local scale = math.clamp(finite(noctalia.getSetting("shell.corner_radius_scale"), 1), 0, 2)
    local borders = noctalia.getSetting("shell.panel.borders") ~= false
    local width = math.clamp(finite(noctalia.getSetting("shell.panel.border_width"), 1), 0, 20)
    local color = noctalia.getSetting("shell.panel.border_color")
    if type(color) ~= "string" or color == "" then
        color = "outline"
    end
    return {
        key = key,
        gap = 6,
        padding = 10,
        radius = 8 * scale,
        fill = "surface_variant/0.35",
        border = color,
        borderWidth = borders and width or 0,
    }
end
local function openLink(url)
    -- Restrict links to the selected forge origin.
    local host = snapshot.provider == "github" and "https://github.com/"
        or (
            snapshot.provider == "gitlab" and ((snapshot.base_url or "") .. "/")
            or "https://tangled.org/"
        )
    if snapshot.provider == "gitlab" and not snapshot.base_url then
        return
    end
    if type(url) ~= "string" or url:sub(1, #host) ~= host then
        return
    end
    if not noctalia.commandExists("xdg-open") then
        inputError = "Missing xdg-open. Install it to open links."
        render()
        return
    end
    noctalia.runAsync({ "xdg-open", url })
end
local function selectRepository(repository)
    query, inputError = "", ""
    filterRevision += 1
    tab = "pulls"
    send({ op = "repository", repository = repository })
    render()
end
function onInspectRepository()
    local value = repositoryDraft:match("^%s*(.-)%s*$")
    local owner, name = value:match("^([%w][%w%.:%-]*)/([%w_%.%-]+)$")
    if
        (snapshot.provider == "gitlab" and not GitLab.validRepository(value))
        or (
            snapshot.provider ~= "gitlab"
            and (not owner or name == "." or name == ".." or #value > 200)
        )
    then
        inputError = snapshot.provider == "gitlab" and "Enter a project as group/subgroup/project."
            or "Enter a repository as owner/name."
        render()
        return
    end
    selectRepository(value)
end
local function repositoryRow(item)
    return ui.column(surface(snapshot.provider .. "-repo-" .. item.name), {
        ui.row({ gap = 8, align = "center" }, {
            ui.glyph({ name = "git-branch", size = 18, color = "primary" }),
            ui.label({
                text = item.name,
                fontSize = 14,
                fontWeight = "semibold",
                flexGrow = 1,
                maxLines = 1,
            }),
            ui.button({
                text = "Inspect",
                controlSize = "sm",
                onClick = function()
                    selectRepository(item.name)
                end,
            }),
            ui.button({
                glyph = "external-link",
                controlSize = "sm",
                tooltip = "Open repository",
                onClick = function()
                    openLink(item.url)
                end,
            }),
        }),
        label(item.description ~= "" and item.description or "No description"),
    })
end
local function workRow(item)
    local meta = item.repository .. (item.id ~= "" and " · " .. item.id or "")
    if item.author and item.author ~= "" then
        meta ..= " · " .. item.author
    end
    return ui.column(
        surface(
            snapshot.provider
                .. "-"
                .. tab
                .. "-"
                .. (item.uri or (item.repository .. "-" .. item.id))
        ),
        {
            ui.row({ gap = 8, align = "center" }, {
                ui.glyph({
                    name = tab == "pulls" and "git-pull-request"
                        or (tab == "notifications" and "bell" or "circle-dot"),
                    size = 18,
                    color = "primary",
                }),
                ui.label({
                    text = item.title,
                    fontSize = 14,
                    fontWeight = "semibold",
                    flexGrow = 1,
                    maxLines = 2,
                }),
                ui.button({
                    glyph = "external-link",
                    controlSize = "sm",
                    tooltip = item.linkLabel or "Open in browser",
                    onClick = function()
                        openLink(item.url)
                    end,
                }),
            }),
            label(meta),
            label(
                item.state .. (item.updatedAt ~= "" and " · " .. item.updatedAt:sub(1, 10) or "")
            ),
        }
    )
end
local activityCaches = {}
local function supportsContributions()
    if snapshot.capabilities then
        return snapshot.capabilities.contributions == true
    end
    return snapshot.provider ~= "tangled"
end
local function activityIdentity(value)
    return value.provider .. ":" .. (value.base_url or "") .. ":" .. (value.account or "")
end
-- Remove private image files left by the previous renderer; native charts never write data.
local oldChartDirectory = noctalia.pluginDataDir()
if oldChartDirectory then
    for _, provider in ipairs({ "tangled", "github", "gitlab" }) do
        noctalia.removeFile(oldChartDirectory .. "/activity-" .. provider .. ".svg")
        noctalia.removeFile(oldChartDirectory .. "/activity-" .. provider .. ".svg.tmp")
    end
end
local function monthIndex(cached)
    for i, month in ipairs(cached.data.months) do
        if month.date == cached.selectedMonth then
            return i
        end
    end
    return #cached.data.months
end
local function prepareActivity()
    if type(snapshot.contributions) ~= "table" then
        return nil
    end
    local identity = activityIdentity(snapshot)
    local cached = activityCaches[snapshot.provider]
    if cached and cached.identity ~= identity then
        cached = nil
    end
    local versions = snapshot.versions or {}
    local key = tostring(versions.contributions or 0) .. ":" .. tostring(versions.activity or 0)
    if not cached or cached.key ~= key then
        local data = Activity.fromCalendar(snapshot.contributions)
        local nextCache = {
            identity = identity,
            key = key,
            data = data,
            layout = Activity.layout(data),
            selectedMonth = cached and cached.selectedMonth or data.months[#data.months].date,
            metric = cached and cached.metric,
        }
        local selected = data.months[monthIndex(nextCache)]
        local firstReported
        for _, metric in ipairs(nextCache.layout.metrics) do
            if selected.values[metric] ~= nil then
                firstReported = firstReported or metric
            end
        end
        if not nextCache.metric or selected.values[nextCache.metric] == nil then
            nextCache.metric = firstReported or nextCache.layout.metrics[1]
        end
        nextCache.selectedMonth = selected.date
        cached = nextCache
        activityCaches[snapshot.provider] = cached
    end
    return cached
end
local function activeChart(cached)
    return opened and activityCaches[snapshot.provider] == cached
end
-- Native Box starts with an opaque black fill; plot spacers must explicitly clear it.
local function curveLayers(cached)
    if cached.curves then
        return cached.curves
    end
    local layout, layers = cached.layout, {}
    for _, metric in ipairs(layout.metrics) do
        for i = 1, #cached.data.months - 1 do
            local first, last = layout.points[metric][i], layout.points[metric][i + 1]
            if
                first.value ~= nil
                and last.value ~= nil
                and not first.lowerBound
                and not last.lowerBound
            then
                local left, width = first.x + 7, last.x - first.x
                table.insert(
                    layers,
                    ui.row({
                        key = "activity-curve-layer-" .. metric .. "-" .. tostring(i),
                        width = layout.width,
                        height = layout.height,
                        gap = 0,
                    }, {
                        ui.box({ width = left, height = layout.height, fill = "#00000000" }),
                        ui.graph({
                            key = "activity-curve-" .. metric .. "-" .. tostring(i),
                            width = width,
                            height = layout.height,
                            values = Activity.curveValues(first, last, layout.height),
                            color = last.value >= first.value and "primary" or "error",
                            lineWidth = 1,
                            fillOpacity = 0,
                            opacity = 0.35,
                        }),
                        ui.box({
                            width = layout.width - left - width,
                            height = layout.height,
                            fill = "#00000000",
                        }),
                    })
                )
            end
        end
    end
    cached.curves = layers
    return layers
end
local METRIC_ICONS = {
    pulls = "git-pull-request",
    commits = "git-commit",
    repos = "git-branch",
    issues = "circle-dot",
    contributions = "chart-line",
}
local function activityStat(cached, metric, index)
    local layout, month = cached.layout, cached.data.months[index]
    local point = layout.points[metric][index]
    local current, selected =
        index == #cached.data.months, cached.selectedMonth == month.date and cached.metric == metric
    local text = Activity.valueText(point.value, point.lowerBound, true)
    if current then
        text ..= " " .. Activity.metricName(metric, snapshot.provider)
    end
    local children = {
        ui.glyph({
            name = METRIC_ICONS[metric],
            size = 14,
            color = selected and "primary" or "on_surface_variant",
        }),
        ui.label({
            text = text,
            fontSize = current and 12 or 11,
            color = selected and "primary" or (current and "on_surface" or "on_surface_variant"),
            maxLines = 1,
        }),
    }
    local previous = layout.points[metric][index - 1]
    if
        previous
        and previous.value ~= nil
        and point.value ~= nil
        and not previous.lowerBound
        and not point.lowerBound
        and (current or #text <= 3)
    then
        local delta = point.value - previous.value
        table.insert(
            children,
            ui.glyph({
                name = delta == 0 and "minus"
                    or (delta > 0 and "arrow-up-right" or "arrow-down-right"),
                size = 12,
                color = delta == 0 and "on_surface_variant" or (delta > 0 and "primary" or "error"),
            })
        )
    end
    return ui.row({
        key = "activity-stat-" .. month.date .. "-" .. metric,
        height = 26,
        gap = 3,
        align = "center",
        fill = (current or selected) and "surface_variant" or "surface",
        radius = 3,
        tooltip = month.date
            .. " · "
            .. Activity.valueText(point.value, point.lowerBound, false)
            .. " "
            .. Activity.metricName(metric, snapshot.provider),
        onClick = point.value ~= nil and function()
            if activeChart(cached) then
                cached.selectedMonth, cached.metric = month.date, metric
                render()
            end
        end or nil,
    }, children)
end
local function activityLabels(cached)
    local layout, columns = cached.layout, {}
    for i, month in ipairs(cached.data.months) do
        local sorted = table.clone(layout.metrics)
        table.sort(sorted, function(a, b)
            return layout.points[a][i].y < layout.points[b][i].y
        end)
        local children, cursor = {}, 0
        for _, metric in ipairs(sorted) do
            local top = layout.points[metric][i].y - 13
            if top > cursor then
                table.insert(children, ui.box({ height = top - cursor, fill = "#00000000" }))
            end
            table.insert(children, activityStat(cached, metric, i))
            cursor = top + 26
        end
        table.insert(children, ui.box({ height = 186 - cursor, fill = "#00000000" }))
        table.insert(
            children,
            ui.label({
                text = month.label .. (i == #cached.data.months and " · now" or ""),
                height = 24,
                fontSize = 12,
                maxLines = 1,
                color = i == #cached.data.months and "on_surface" or "on_surface_variant",
            })
        )
        local parts = {}
        if i > 1 then
            table.insert(
                parts,
                ui.box({ width = 1, height = layout.height, fill = "outline/0.25" })
            )
        end
        table.insert(
            parts,
            ui.column({
                key = "activity-column-" .. month.date,
                width = layout.columns[i].width - (i > 1 and 1 or 0),
                height = layout.height,
                gap = 0,
                paddingH = i > 1 and 7 or 8,
                align = "start",
            }, children)
        )
        table.insert(
            columns,
            ui.row({ width = layout.columns[i].width, height = layout.height, gap = 0 }, parts)
        )
    end
    return ui.row(
        { key = "activity-labels", width = layout.width, height = layout.height, gap = 0 },
        columns
    )
end
local function contributionSection()
    local cached = supportsContributions() and prepareActivity() or nil
    if not cached then
        return ui.column({ key = "activity-unavailable", gap = 6 }, {
            label(
                (snapshot.errors or {}).contributions
                    or (
                        (snapshot.loading or {}).contributions and "Loading activity…"
                        or "Activity unavailable."
                    ),
                14
            ),
            ui.button({
                text = "Open profile activity",
                controlSize = "sm",
                onClick = function()
                    send({ op = "profile", provider = snapshot.provider })
                end,
            }),
        })
    end
    local data, layout = cached.data, cached.layout
    local current = layout.columns[#layout.columns]
    local layers = {
        ui.row(
            { key = "activity-backdrop", width = layout.width, height = layout.height, gap = 0 },
            {
                ui.box({ width = current.left, height = layout.height, fill = "#00000000" }),
                ui.box({
                    width = current.width,
                    height = layout.height,
                    fill = "surface_variant",
                }),
            }
        ),
    }
    for _, curve in ipairs(curveLayers(cached)) do
        table.insert(layers, curve)
    end
    table.insert(layers, activityLabels(cached))
    local index = monthIndex(cached)
    local month, metric = data.months[index], cached.metric
    local change, color = Activity.comparison(data, index, metric)
    local children = {
        label("Activity · last 6 months", 14),
        -- API34 Flex preserves negative gaps: equal-height layers share the same origin.
        ui.column({
            key = "activity-overlay",
            width = layout.width,
            height = layout.height,
            gap = -layout.height,
        }, layers),
        ui.row(
            { key = "activity-inspector", justify = "space_between", align = "center", gap = 6 },
            {
                label(
                    month.date
                        .. " · "
                        .. Activity.valueText(
                            month.values[metric],
                            month.lowerBounds[metric],
                            false
                        )
                        .. " "
                        .. Activity.metricName(metric, snapshot.provider),
                    12,
                    "on_surface"
                ),
                label(change, 11, color),
            }
        ),
        label("Independent scales · current month partial · select a count for details", 11),
    }
    if data.note and data.note ~= "" then
        table.insert(children, label(data.note, 11))
    end
    if (snapshot.errors or {}).contributions then
        table.insert(children, label(snapshot.errors.contributions, 11, "error"))
    end
    return ui.column({ key = "activity-section", gap = 6 }, children)
end
render = function()
    if not opened then
        return
    end
    if snapshot.provider == "tangled" and tab == "notifications" then
        tab = "repositories"
    end
    if not supportsContributions() or not snapshot.contributions then
        activityCaches[snapshot.provider] = nil
    end
    local forge = snapshot.provider == "github" and "GitHub"
        or (snapshot.provider == "gitlab" and "GitLab" or "Tangled")
    local headerActions = {
        ui.button({
            key = "profile-tangled",
            glyph = "git-branch",
            controlSize = "sm",
            tooltip = "Open Tangled profile",
            onClick = function()
                send({ op = "profile", provider = "tangled" })
            end,
        }),
        ui.button({
            key = "profile-github",
            glyph = "brand-github",
            controlSize = "sm",
            tooltip = "Open GitHub profile",
            onClick = function()
                send({ op = "profile", provider = "github" })
            end,
        }),
        ui.button({
            key = "profile-gitlab",
            glyph = "git-branch",
            controlSize = "sm",
            tooltip = "Open GitLab profile",
            onClick = function()
                send({ op = "profile", provider = "gitlab" })
            end,
        }),
        ui.button({
            glyph = "refresh",
            tooltip = "Refresh",
            controlSize = "sm",
            enabled = snapshot.status ~= "loading",
            onClick = function()
                send({ op = "refresh" })
            end,
        }),
        ui.button({
            glyph = "settings",
            tooltip = "Forges settings",
            controlSize = "sm",
            onClick = function()
                noctalia.openSettings()
            end,
        }),
    }
    if noctalia.getSetting("shell.show_close_buttons") ~= false then
        table.insert(
            headerActions,
            ui.button({
                glyph = "x",
                tooltip = "Close",
                controlSize = "sm",
                onClick = function()
                    panel.close()
                end,
            })
        )
    end
    local providers = {}
    for _, value in ipairs({ "tangled", "github", "gitlab" }) do
        table.insert(
            providers,
            ui.button({
                key = "provider-" .. value,
                text = value == "tangled" and "Tangled"
                    or (value == "gitlab" and "GitLab" or "GitHub"),
                flexGrow = 1,
                variant = snapshot.provider == value and "primary" or "default",
                onClick = function()
                    if snapshot.provider == value then
                        return
                    end
                    query, inputError = "", ""
                    filterRevision += 1
                    send({ op = "provider", provider = value })
                end,
            })
        )
    end
    local tabs = {}
    local definitions = {
        { "repositories", "Repositories" },
        { "pulls", snapshot.provider == "gitlab" and "Merge requests" or "Pull requests" },
        { "issues", "Issues" },
    }
    if snapshot.provider ~= "tangled" then
        table.insert(
            definitions,
            { "notifications", snapshot.provider == "gitlab" and "To-dos" or "Inbox" }
        )
    end
    for _, definition in ipairs(definitions) do
        local key, title = definition[1], definition[2]
        table.insert(
            tabs,
            ui.button({
                text = title,
                flexGrow = 1,
                controlSize = "sm",
                variant = tab == key and "primary" or "default",
                onClick = function()
                    if tab == key then
                        return
                    end
                    tab, query = key, ""
                    filterRevision += 1
                    send({ op = "view", view = key })
                    render()
                end,
            })
        )
    end
    local context = snapshot.repository or ""
    if context == "" then
        context = snapshot.provider == "tangled"
                and "Open authored work · newest 100 public records"
            or (
                snapshot.provider == "gitlab"
                    and "Authored, assigned, or review-requested · latest 30"
                or "Your open work · all repositories"
            )
    end
    if tab == "repositories" then
        context = "Your repositories · inspect any repository"
    end
    if tab == "notifications" then
        context = snapshot.provider == "gitlab"
                and "GitLab to-do history · pending and done · read-only"
            or "Available GitHub notification history · read-only"
    end
    local content = {}
    local resourceKey = tab == "overview" and "contributions" or tab
    for _, key in ipairs({ "account", resourceKey }) do
        local message = (snapshot.errors or {})[key]
        if message then
            table.insert(
                content,
                ui.column(surface("error-" .. key), {
                    label(
                        key == "account" and "Forge unavailable"
                            or (key .. " could not be refreshed"),
                        14,
                        "error"
                    ),
                    label(message),
                })
            )
        end
    end
    if inputError ~= "" then
        table.insert(content, label(inputError, 12, "error"))
    end
    if snapshot.action_error then
        table.insert(content, label(snapshot.action_error, 12, "error"))
    end
    if tab == "repositories" then
        table.insert(
            content,
            ui.row({ gap = 6 }, {
                ui.input({
                    key = "repository-" .. snapshot.provider,
                    value = repositoryDraft,
                    placeholder = snapshot.provider == "gitlab"
                            and "Inspect group/subgroup/project"
                        or "Inspect owner/repository",
                    flexGrow = 1,
                    controlSize = "md",
                    onChange = function(value)
                        repositoryDraft = value
                    end,
                    onSubmit = "onInspectRepository",
                }),
                ui.button({ text = "Inspect", controlSize = "md", onClick = "onInspectRepository" }),
            })
        )
    end
    if tab == "notifications" then
        local filters = {}
        local states = snapshot.provider == "gitlab" and { "all", "pending", "done" }
            or { "all", "unread", "read" }
        for _, value in ipairs(states) do
            table.insert(
                filters,
                ui.button({
                    text = value:sub(1, 1):upper() .. value:sub(2),
                    controlSize = "sm",
                    variant = notificationFilter == value and "primary" or "default",
                    onClick = function()
                        notificationFilter, inboxPage = value, 1
                        render()
                    end,
                })
            )
        end
        table.insert(content, ui.row({ gap = 6 }, filters))
    end
    local items = tab ~= "overview" and (snapshot[tab] or {}) or {}
    local matching = {}
    for _, item in ipairs(items) do
        local text = (item.name or item.title or "")
            .. " "
            .. (item.repository or "")
            .. " "
            .. (item.description or "")
        local matchesRead = tab ~= "notifications"
            or notificationFilter == "all"
            or item.state == notificationFilter
        if matchesRead and (query == "" or text:lower():find(query:lower(), 1, true)) then
            table.insert(matching, item)
        end
    end
    local maxPage = math.max(1, math.ceil(#matching / INBOX_PAGE_SIZE))
    inboxPage = math.clamp(inboxPage, 1, maxPage)
    local first = tab == "notifications" and ((inboxPage - 1) * INBOX_PAGE_SIZE + 1) or 1
    local last = math.min(#matching, tab == "notifications" and (inboxPage * INBOX_PAGE_SIZE) or 50)
    local shown = 0
    for index = first, last do
        local item = matching[index]
        table.insert(content, tab == "repositories" and repositoryRow(item) or workRow(item))
        shown += 1
    end
    if tab == "notifications" and maxPage > 1 then
        table.insert(
            content,
            ui.row({ gap = 8, align = "center" }, {
                ui.button({
                    key = "inbox-previous",
                    text = "Previous",
                    controlSize = "sm",
                    enabled = inboxPage > 1,
                    onClick = function()
                        inboxPage = math.max(1, inboxPage - 1)
                        render()
                    end,
                }),
                label("Page " .. tostring(inboxPage) .. " / " .. tostring(maxPage)),
                ui.button({
                    key = "inbox-next",
                    text = "Next",
                    controlSize = "sm",
                    enabled = inboxPage < maxPage,
                    onClick = function()
                        inboxPage = math.min(maxPage, inboxPage + 1)
                        render()
                    end,
                }),
            })
        )
    end
    if tab == "notifications" and snapshot.notification_has_more then
        table.insert(
            content,
            ui.button({
                text = snapshot.provider == "gitlab" and "Load older to-dos"
                    or "Load older notifications",
                controlSize = "md",
                enabled = not (snapshot.loading or {}).notifications,
                onClick = function()
                    send({ op = "notifications_more" })
                end,
            })
        )
    end
    if shown == 0 and tab ~= "overview" then
        local empty = "No matching results."
        if query == "" then
            if snapshot.status == "loading" then
                empty = "Loading " .. forge .. "…"
            elseif snapshot.status == "auth_error" or snapshot.status == "missing_cli" then
                empty = "Sign in or retry to load results."
            elseif tab == "repositories" then
                empty = "No repositories returned. Inspect a repository above."
            elseif (snapshot.errors or {})[tab] then
                empty = "Results unavailable. Retry with Refresh."
            else
                empty = tab == "notifications"
                        and ("No " .. (notificationFilter == "all" and "" or notificationFilter .. " ") .. "notifications in loaded results.")
                    or "No open "
                        .. (tab == "pulls" and (snapshot.provider == "gitlab" and "merge requests" or "pull requests") or "issues")
                        .. " in this scope."
            end
        end
        table.insert(content, label(empty, 14))
    end
    local status = snapshot.status == "loading" and "Refreshing…" or "Not refreshed"
    if snapshot.status ~= "loading" and snapshot.updated_at then
        status = "Updated " .. os.date("%H:%M", snapshot.updated_at)
    end
    if snapshot.stale and snapshot.status ~= "loading" then
        status = "Refresh failed · showing last good results"
    end
    local scopeChildren = {
        ui.label({
            text = context,
            fontSize = 12,
            color = "on_surface_variant",
            flexGrow = 1,
            maxLines = 1,
        }),
    }
    if (snapshot.repository or "") ~= "" and (tab == "pulls" or tab == "issues") then
        table.insert(
            scopeChildren,
            ui.button({
                text = snapshot.provider == "tangled" and "Authored work" or "All work",
                controlSize = "sm",
                onClick = function()
                    selectRepository("")
                end,
            })
        )
    end
    panel.render(ui.column({ padding = 16, gap = 10, flexGrow = 1 }, {
        ui.row({ align = "center", gap = 8 }, {
            ui.glyph({ name = "git-branch", size = 22, color = "primary" }),
            ui.label({ text = "Forges", fontSize = 18, fontWeight = "bold", flexGrow = 1 }),
            ui.row({ gap = 6 }, headerActions),
        }),
        ui.row({ key = "provider-switch", gap = 6 }, providers),
        contributionSection(),
        label(
            (snapshot.account or "") ~= "" and ("@" .. snapshot.account .. " · " .. forge)
                or (forge .. " · account unavailable")
        ),
        ui.row({ gap = 4 }, tabs),
        ui.row({ gap = 6, align = "center" }, scopeChildren),
        ui.input({
            key = "filter-" .. snapshot.provider .. "-" .. tab .. "-" .. tostring(filterRevision),
            placeholder = "Filter "
                .. (
                    tab == "pulls"
                        and (snapshot.provider == "gitlab" and "merge requests" or "pull requests")
                    or tab
                ),
            value = query,
            onChange = function(value)
                query, inboxPage = value, 1
                render()
            end,
        }),
        ui.scroll(
            { key = "forges-" .. snapshot.provider .. "-" .. tab, flexGrow = 1, gap = 8 },
            content
        ),
        ui.row({ justify = "space_between" }, {
            label(status),
            label(
                tostring(shown)
                    .. " shown · "
                    .. (
                        tab == "notifications" and ("of " .. tostring(#matching) .. " loaded")
                        or "first page"
                    )
            ),
        }),
    }))
end
noctalia.state.watch("forges.snapshot", function(value)
    if type(value) ~= "table" then
        return
    end
    if value.provider ~= snapshot.provider then
        query, repositoryDraft, inputError = "", "", ""
        notificationFilter, inboxPage = "all", 1
    end
    local cached = activityCaches[value.provider]
    local identity = activityIdentity(value)
    if
        cached
        and (
            not value.contributions
            or cached.identity ~= identity
            or (value.capabilities and value.capabilities.contributions == false)
        )
    then
        activityCaches[value.provider] = nil
    end
    snapshot = value
    tab = snapshot.view == "overview" and "repositories" or (snapshot.view or "repositories")
    render()
end)
function onOpen()
    opened = true
    panel.setWantsSecondTicks(false)
    render()
end
function onClose()
    opened = false
    panel.setWantsSecondTicks(false)
    panel.setNeedsFrameTick(false)
end
