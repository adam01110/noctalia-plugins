--!nonstrict
-- Native work queue: forge -> repository scope -> bounded, readable rows.
local opened = false
local snapshot = noctalia.state.get("forges.snapshot")
    or { provider = "tangled", status = "loading" }
local tab = "repositories"
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
    -- Both providers supply HTTPS URLs. Never launch an arbitrary URI scheme.
    local host = snapshot.provider == "github" and "https://github.com/" or "https://tangled.org/"
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
    if not owner or name == "." or name == ".." or #value > 200 then
        inputError = "Enter a repository as owner/name."
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
        surface(snapshot.provider .. "-" .. tab .. "-" .. item.repository .. "-" .. item.id),
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
render = function()
    if not opened then
        return
    end
    if snapshot.provider ~= "github" and tab == "notifications" then
        tab = "repositories"
    end
    local forge = snapshot.provider == "github" and "GitHub" or "Tangled"
    local headerActions = {
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
    for _, value in ipairs({ "tangled", "github" }) do
        table.insert(
            providers,
            ui.button({
                text = value == "tangled" and "Tangled" or "GitHub",
                flexGrow = 1,
                variant = snapshot.provider == value and "primary" or "default",
                onClick = function()
                    if snapshot.provider == value then
                        return
                    end
                    tab, query, inputError = "repositories", "", ""
                    send({ op = "provider", provider = value })
                end,
            })
        )
    end
    local tabs = {}
    local definitions =
        { { "repositories", "Repositories" }, { "pulls", "Pull requests" }, { "issues", "Issues" } }
    if snapshot.provider == "github" then
        table.insert(definitions, { "notifications", "Inbox" })
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
                    render()
                end,
            })
        )
    end
    local context = snapshot.repository or ""
    if context == "" then
        context = snapshot.provider == "github" and "Your open work · all repositories"
            or "Choose a repository to view work"
    end
    if tab == "repositories" then
        context = "Your repositories · inspect any repository"
    end
    if tab == "notifications" then
        context = "GitHub notifications · read-only"
    end
    local content = {}
    for _, key in ipairs({ "account", "repositories", "pulls", "issues", "notifications" }) do
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
    if tab == "repositories" then
        table.insert(
            content,
            ui.row({ gap = 6 }, {
                ui.input({
                    key = "repository-" .. snapshot.provider,
                    value = repositoryDraft,
                    placeholder = "Inspect owner/repository",
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
    local items = snapshot[tab] or {}
    local shown = 0
    for _, item in ipairs(items) do
        if shown >= 50 then
            break
        end
        local text = (item.name or item.title or "")
            .. " "
            .. (item.repository or "")
            .. " "
            .. (item.description or "")
        if query == "" or text:lower():find(query:lower(), 1, true) then
            table.insert(content, tab == "repositories" and repositoryRow(item) or workRow(item))
            shown += 1
        end
    end
    if shown == 0 then
        local empty = "No matching results."
        if query == "" then
            if snapshot.status == "loading" then
                empty = "Loading " .. forge .. "…"
            elseif snapshot.status == "auth_error" or snapshot.status == "missing_cli" then
                empty = "Sign in or retry to load results."
            elseif tab == "repositories" then
                empty = "No repositories returned. Inspect a repository above."
            elseif snapshot.provider == "tangled" and (snapshot.repository or "") == "" then
                empty = "Choose a repository from Repositories."
            elseif (snapshot.errors or {})[tab] then
                empty = "Results unavailable. Retry with Refresh."
            else
                empty = tab == "notifications" and "No unread notifications."
                    or "No open "
                        .. (tab == "pulls" and "pull requests" or "issues")
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
    if
        snapshot.provider == "github"
        and (snapshot.repository or "") ~= ""
        and tab ~= "notifications"
    then
        table.insert(
            scopeChildren,
            ui.button({
                text = "All work",
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
        ui.row({ gap = 6 }, providers),
        label(
            (snapshot.account or "") ~= "" and ("@" .. snapshot.account .. " · " .. forge)
                or (forge .. " · account unavailable")
        ),
        ui.row({ gap = 4 }, tabs),
        ui.row({ gap = 6, align = "center" }, scopeChildren),
        ui.input({
            key = "filter-" .. snapshot.provider .. "-" .. tab .. "-" .. tostring(filterRevision),
            placeholder = "Filter " .. (tab == "pulls" and "pull requests" or tab),
            value = query,
            onChange = function(value)
                query = value
                render()
            end,
        }),
        ui.scroll(
            { key = "forges-" .. snapshot.provider .. "-" .. tab, flexGrow = 1, gap = 8 },
            content
        ),
        ui.row(
            { justify = "space_between" },
            { label(status), label(tostring(shown) .. " shown · first page") }
        ),
    }))
end
noctalia.state.watch("forges.snapshot", function(value)
    if type(value) ~= "table" then
        return
    end
    if value.provider ~= snapshot.provider then
        query, repositoryDraft, inputError = "", "", ""
    end
    snapshot = value
    render()
end)
function onOpen()
    opened = true
    render()
end
function onClose()
    opened = false
end
function onConfigChanged()
    render()
end
