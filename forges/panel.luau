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
local calendars = {}
local calendar = {}
local imageRevision = 0
local function supportsContributions()
    if snapshot.capabilities then
        return snapshot.capabilities.contributions == true
    end
    return snapshot.provider ~= "tangled"
end
local function clearCalendar(provider)
    local cached = calendars[provider]
    if cached and cached.path then
        noctalia.removeFile(cached.path)
    end
    calendars[provider] = nil
end
local function chartColors()
    local function color(role, fallback)
        local value = noctalia.getColor(role)
        return type(value) == "string" and value:match("^#%x%x%x%x%x%x$") and value or fallback
    end
    return {
        background = color("surface", "#202124"),
        current = color("surface_variant", "#303134"),
        text = color("on_surface", "#e8eaed"),
        border = color("outline", "#777777"),
        rising = color("primary", "#a8c7fa"),
        falling = color("error", "#f28b82"),
    }
end
local function paletteKey(colors)
    return table.concat({
        colors.background,
        colors.current,
        colors.text,
        colors.border,
        colors.rising,
        colors.falling,
    }, ":")
end
local function prepareCalendar()
    local data = snapshot.contributions
    if type(data) ~= "table" then
        return nil
    end
    local identity = snapshot.provider
        .. ":"
        .. (snapshot.base_url or "")
        .. ":"
        .. (snapshot.account or "")
    local cached = calendars[snapshot.provider]
    if cached and cached.identity ~= identity then
        clearCalendar(snapshot.provider)
        cached = nil
    end
    local colors = chartColors()
    local key = identity
        .. ":"
        .. tostring((snapshot.versions or {}).contributions or 0)
        .. ":"
        .. tostring((snapshot.versions or {}).activity or 0)
        .. ":"
        .. paletteKey(colors)
    if not cached or cached.key ~= key then
        local activity = Activity.fromCalendar(data)
        local svg = Activity.svg(activity, colors, snapshot.provider)
        if cached and cached.svg == svg then
            cached.key, cached.data, cached.error = key, activity, nil
            cached.palette = paletteKey(colors)
            calendar = cached
            return activity
        end
        local directory = noctalia.pluginDataDir()
        local path = directory and (directory .. "/activity-" .. snapshot.provider .. ".svg")
        local temporary = path and (path .. ".tmp")
        local written = path
            and noctalia.mkdirAll(directory)
            and noctalia.writeFile(temporary, svg)
            and noctalia.renameFile(temporary, path)
        if temporary then
            noctalia.removeFile(temporary)
        end
        if written then
            imageRevision += 1
            cached = {
                key = key,
                identity = identity,
                data = activity,
                path = path,
                svg = svg,
                palette = paletteKey(colors),
                selectedMonth = cached and cached.selectedMonth or 6,
                -- A new image key forces API34 to reread the bounded per-provider SVG file.
                node = ui.image({
                    key = "activity-chart-" .. tostring(imageRevision),
                    path = path,
                    width = 548,
                    height = 210,
                    fit = "contain",
                    tooltip = "Monthly activity · each metric scaled independently · select a month below for exact counts",
                }),
            }
            calendars[snapshot.provider] = cached
        else
            cached = cached or { identity = identity, data = activity, selectedMonth = 6 }
            cached.error = "Could not write activity chart. Monthly counts remain available below."
        end
    end
    if cached.key == key then
        cached.error = nil
    end
    calendar = cached
    return cached.data
end
local function contributionSection()
    if not supportsContributions() then
        return ui.row(
            { key = "external-activity", gap = 8, align = "center", justify = "space_between" },
            {
                label("Activity", 14),
                ui.button({
                    text = "Open profile activity",
                    controlSize = "sm",
                    onClick = function()
                        send({ op = "profile", provider = snapshot.provider })
                    end,
                }),
            }
        )
    end
    local data = prepareCalendar()
    if not data then
        return ui.column({ key = "contribution-calendar", height = 170, justify = "center" }, {
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
    local months = {}
    for i, month in ipairs(data.months) do
        table.insert(
            months,
            ui.button({
                key = "activity-month-" .. tostring(i),
                text = month.label,
                controlSize = "sm",
                flexGrow = 1,
                tooltip = Activity.detail(data, i, snapshot.provider),
                onClick = function()
                    calendar.selectedMonth = i
                    render()
                end,
            })
        )
    end
    local children = { label("Activity · last 6 months", 14) }
    if calendar.node then
        table.insert(children, calendar.node)
    end
    table.insert(children, ui.row({ key = "activity-months", gap = 2 }, months))
    table.insert(
        children,
        label(Activity.detail(data, calendar.selectedMonth or 6, snapshot.provider), 11)
    )
    table.insert(children, label((data.note or "") .. " · current month partial", 11))
    if calendar.error then
        table.insert(children, label(calendar.error, 11, "error"))
    end
    if (snapshot.errors or {}).contributions then
        table.insert(children, label(snapshot.errors.contributions, 11, "error"))
    end
    return ui.column({ key = "activity-section", gap = 6 }, children)
end
function onFrameTick()
    panel.setNeedsFrameTick(false)
end
render = function()
    if not opened then
        return
    end
    if snapshot.provider == "tangled" and tab == "notifications" then
        tab = "repositories"
    end
    if not supportsContributions() or not snapshot.contributions then
        clearCalendar(snapshot.provider)
        calendar = {}
        panel.setNeedsFrameTick(false)
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
    local cached = calendars[value.provider]
    local identity = (value.provider or "")
        .. ":"
        .. (value.base_url or "")
        .. ":"
        .. (value.account or "")
    if
        cached
        and (
            not value.contributions
            or cached.identity ~= identity
            or (value.capabilities and value.capabilities.contributions == false)
        )
    then
        clearCalendar(value.provider)
    end
    snapshot = value
    tab = snapshot.view == "overview" and "repositories" or (snapshot.view or "repositories")
    render()
end)
function onOpen()
    opened = true
    panel.setWantsSecondTicks(true)
    render()
end
function onClose()
    opened = false
    panel.setWantsSecondTicks(false)
    panel.setNeedsFrameTick(false)
end
function update()
    if opened and calendar.data and calendar.palette ~= paletteKey(chartColors()) then
        render()
    end
end
