--!nonstrict
local GitHub = (function()
    -- GITHUB_SOURCE
end)()
local Data = (function()
    -- DATA_SOURCE
end)()
local Tangled = (function()
    -- TANGLED_SOURCE
end)()

local function copy(value)
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for key, item in pairs(value) do
        result[key] = copy(item)
    end
    return result
end
local config, settings, values, watches, queue, exists, failStart
local calls, lastPanel, panelRenders, lastCommand, lastLaunch, glyph, tooltip, toggled
local noctalia = {
    nowMs = function()
        return 100
    end,
    openSettings = function() end,
    getConfig = function(key)
        return config[key]
    end,
    getSetting = function(key)
        return settings[key]
    end,
    commandExists = function()
        return exists
    end,
    setUpdateInterval = function(value)
        assert(value >= 300000 and value <= 3600000)
    end,
    json = {
        decode = function(value)
            if type(value) ~= "table" then
                error("bad json")
            end
            return value
        end,
    },
    state = {
        get = function(key)
            return values[key]
        end,
        set = function(key, value)
            values[key] = copy(value)
            if key == "forges.command" then
                lastCommand = value
            end
            for _, watcher in ipairs(watches[key] or {}) do
                watcher(copy(value))
            end
        end,
        watch = function(key, callback)
            watches[key] = watches[key] or {}
            table.insert(watches[key], callback)
        end,
    },
    runAsync = function(argv, callback)
        calls += 1
        if not callback then
            lastLaunch = argv
            return true
        end
        if failStart then
            return false
        end
        table.insert(queue, { argv = argv, callback = callback })
        return true
    end,
    togglePanel = function(id)
        toggled = id
    end,
}
local function boot(options)
    config = options or {}
    settings, values, watches, queue = {}, {}, {}, {}
    exists, failStart, calls = true, false, 0
end
local function service()
    -- SERVICE_SOURCE
end
local function snapshot()
    return assert(values["forges.snapshot"])
end
local function send(value)
    noctalia.state.set("forges.command", value)
end
local function respond(value, code, stderr)
    local request = assert(table.remove(queue, 1), "Expected queued request")
    request.callback({
        exitCode = code or 0,
        stdout = value,
        stderr = stderr or "secret must never appear in UI",
    })
    return request.argv
end
local tgRepo = { items = { { author = "alice.test", name = "project", description = "Example" } } }
local tgWork = {
    items = {
        { rkey = "abc123", title = "A task", author = { handle = "alice.test" }, state = "open" },
    },
}
local function tangleresults()
    respond({ authenticated = true, handle = "alice.test" })
    respond(tgRepo)
    respond(tgWork)
    respond({ items = {} })
end
boot()
service()
assert(queue[1].argv[1] == "tg", "Tangled is the default")
tangleresults()
assert(snapshot().status == "ready" and snapshot().account == "alice.test")
assert(snapshot().repository == "alice.test/project" and #snapshot().pulls == 1)
assert(snapshot().pulls[1].url == "https://tangled.org/alice.test/project/pulls")
assert(
    snapshot().pulls[1].linkLabel == "Open repository pull requests",
    "Tangled record keys must not masquerade as numeric AppView web IDs"
)
assert(#snapshot().notifications == 0 and #queue == 0, "Do not fake a Tangled notification API")
local original = copy(snapshot())
send({ op = "refresh" })
local count = calls
send({ op = "refresh" })
assert(calls == count, "Deduplicate same-generation refresh")
respond({ authenticated = true, handle = "alice.test" })
respond(tgRepo)
respond("not-json")
respond({ items = {} })
assert(snapshot().status == "partial" and snapshot().stale and #snapshot().pulls == 1)
assert(
    snapshot().updated_at == original.updated_at,
    "Failure must not advance last successful refresh"
)
assert(not snapshot().errors.pulls:find("secret", 1, true), "Never publish raw stderr")
send({ op = "repository", repository = "--evil/repo" })
assert(#queue == 0)
send({ op = "repository", repository = "alice.test/.." })
assert(#queue == 0)
send({ op = "repository", repository = "alice.test/other;echo" })
assert(#queue == 0)
send({ op = "repository", repository = "bob.test/other" })
assert(#snapshot().pulls == 0 and snapshot().repository == "bob.test/other")
respond({ authenticated = true, handle = "alice.test" })
respond(tgRepo)
local oldPull = assert(table.remove(queue, 1))
local oldIssue = assert(table.remove(queue, 1))
send({ op = "repository", repository = "bob.test/new" })
oldPull.callback({ exitCode = 0, stdout = tgWork })
oldIssue.callback({ exitCode = 0, stdout = tgWork })
assert(
    #snapshot().pulls == 0 and #snapshot().issues == 0,
    "Ignore callbacks from old repository scope"
)
respond({ authenticated = true, handle = "alice.test" })
respond(tgRepo)
respond({ items = {} })
respond({ items = {} })
send({ op = "refresh" })
local delayed = assert(table.remove(queue, 1))
send({ op = "provider", provider = "github" })
assert(
    snapshot().provider == "github" and snapshot().account == "" and #snapshot().repositories == 0
)
delayed.callback({ exitCode = 0, stdout = { authenticated = true, handle = "old.test" } })
assert(snapshot().account == "", "Ignore callbacks from old provider")
assert(queue[1].argv[1] == "gh")
respond({ login = "octocat" })
respond({ { full_name = "octocat/example", description = "Example" } })
assert(queue[1].argv[3]:find("involves:@me", 1, true))
respond({ items = {} })
respond({ items = {} })
respond({})
assert(
    snapshot().provider == "github"
        and snapshot().status == "ready"
        and snapshot().account == "octocat"
)
send({ op = "refresh" })
respond("", 1, "To get started with GitHub CLI, please run: gh auth login")
assert(
    snapshot().status == "auth_error" and snapshot().account == "" and #snapshot().repositories == 0,
    "GitHub logout clears private account data rather than displaying stale rows"
)
config.provider = "github"
onConfigChanged()
assert(queue[1].argv[1] == "gh")
respond({ login = "other-account" })
respond({})
respond({ items = {} })
respond({ items = {} })
respond({})
assert(snapshot().account == "other-account" and #snapshot().repositories == 0)
boot()
exists = false
service()
assert(snapshot().status == "missing_cli" and #queue == 0)
boot()
failStart = true
service()
assert(
    snapshot().status == "auth_error" and #queue == 0,
    "Failure to spawn must not leave loading stuck"
)
boot()
service()
respond({ authenticated = false })
assert(snapshot().status == "auth_error" and snapshot().account == "")
boot()
service()
respond({ authenticated = true, handle = "new.test" })
respond({ items = {} })
assert(snapshot().status == "ready" and snapshot().repository == "" and #queue == 0)
send({ op = "repository", repository = "tangled.org/core" })
respond({ authenticated = true, handle = "new.test" })
respond({ items = {} })
assert(queue[1].argv[4] == "tangled.org/core", "External repository stays a literal argv element")
respond(tgWork)
respond(tgWork)
send({ op = "refresh" })
respond("unavailable", 1)
assert(
    snapshot().status == "partial" and snapshot().stale and #snapshot().pulls == 1,
    "Network failure during account lookup must retain labelled last-good results"
)
send({ op = "refresh" })
respond({ authenticated = false })
assert(
    snapshot().status == "auth_error" and snapshot().account == "" and #snapshot().pulls == 0,
    "Authentication loss must clear account-owned data"
)
local many = { items = {} }
for index = 1, 100 do
    many.items[index] = tgWork.items[1]
end
assert(#Tangled.normalizeWork(many, "a/b", "issues") == 30)
assert(Tangled.normalizeWork({}, "a/b", "issues") == nil)
assert(Data.work({}) == nil and Tangled.normalizeProfile({ authenticated = false }) == nil)
assert(GitHub.work("issues", "a/b")[3]:find("repo:a/b", 1, true))

local ui = setmetatable({}, {
    __index = function(_, kind)
        return function(props, children)
            return { kind = kind, props = props or {}, children = children or {} }
        end
    end,
})
local panel = {
    render = function(node)
        lastPanel = node
        panelRenders += 1
    end,
    close = function() end,
}
local function panelEntry()
    -- PANEL_SOURCE
end
local function walk(node, visitor)
    visitor(node)
    for _, child in ipairs(node.children or {}) do
        walk(child, visitor)
    end
end
local function find(kind, predicate)
    local result
    walk(lastPanel, function(node)
        if not result and node.kind == kind and predicate(node.props) then
            result = node
        end
    end)
    return result
end
boot()
panelRenders = 0
values["forges.snapshot"] = {
    provider = "tangled",
    account = "alice.test",
    status = "ready",
    repository = "alice.test/project",
    repositories = Tangled.normalizeRepositories(tgRepo),
    pulls = {},
    issues = {},
    errors = {},
}
panelEntry()
onOpen()
local row = assert(find("column", function(props)
    return props.key == "tangled-repo-alice.test/project"
end))
assert(row.props.radius == 8 and row.props.border == "outline" and row.props.borderWidth == 1)
assert(find("input", function(props)
    return props.placeholder == "Inspect owner/repository" and props.value == ""
end))
assert(not find("button", function(props)
    return props.text == "Inbox"
end))
for _, case in ipairs({
    { 0, 0 },
    { 0.5, 4 },
    { 1.5, 12 },
    { -1, 0 },
    { 0 / 0, 8 },
    { math.huge, 8 },
    { "bad", 8 },
}) do
    settings["shell.corner_radius_scale"] = case[1]
    onConfigChanged()
    row = assert(find("column", function(props)
        return props.key == "tangled-repo-alice.test/project"
    end))
    assert(row.props.radius == case[2], "Rows follow finite shell radius scale, including square")
end
settings["shell.panel.borders"] = false
onConfigChanged()
row = assert(find("column", function(props)
    return props.key == "tangled-repo-alice.test/project"
end))
assert(row.props.borderWidth == 0)
settings["shell.panel.borders"], settings["shell.panel.border_width"], settings["shell.panel.border_color"] =
    true, 3, "primary"
onConfigChanged()
row = assert(find("column", function(props)
    return props.key == "tangled-repo-alice.test/project"
end))
assert(row.props.borderWidth == 3 and row.props.border == "primary")
settings["shell.show_close_buttons"] = false
onConfigChanged()
assert(not find("button", function(props)
    return props.tooltip == "Close"
end))
local filter = assert(find("input", function(props)
    return props.placeholder == "Filter repositories"
end))
filter.props.onChange("%literal")
assert(not find("column", function(props)
    return props.key == "tangled-repo-alice.test/project"
end))
local activeKey = assert(find("input", function(props)
    return props.placeholder == "Filter repositories"
end)).props.key
assert(find("button", function(props)
    return props.text == "Repositories"
end)).props.onClick()
assert(find("button", function(props)
    return props.text == "Tangled"
end)).props.onClick()
assert(not find("column", function(props)
    return props.key == "tangled-repo-alice.test/project"
end), "Active tab/provider clicks must not silently clear the visible filter")
filter = assert(find("input", function(props)
    return props.placeholder == "Filter repositories"
end))
assert(filter.props.key == activeKey)
filter.props.onChange("")
assert(find("button", function(props)
    return props.text == "GitHub"
end)).props.onClick()
assert(lastCommand.op == "provider" and lastCommand.provider == "github")
assert(find("button", function(props)
    return props.text == "Inspect" and props.controlSize == "sm"
end)).props.onClick()
assert(lastCommand.op == "repository" and lastCommand.repository == "alice.test/project")
assert(find("button", function(props)
    return props.text == "Repositories"
end)).props.onClick()
assert(find("button", function(props)
    return props.tooltip == "Open repository"
end)).props.onClick()
assert(lastLaunch[1] == "xdg-open" and lastLaunch[2] == "https://tangled.org/alice.test/project")
local renders = panelRenders
onClose()
noctalia.state.set("forges.snapshot", values["forges.snapshot"])
assert(panelRenders == renders, "Closed panel must not rebuild its tree")
local barWidget = {
    setGlyph = function(value)
        glyph = value
    end,
    setText = function() end,
    setTooltip = function(value)
        tooltip = value
    end,
}
local function widgetEntry()
    -- WIDGET_SOURCE
end
widgetEntry()
assert(glyph == "git-branch" and tooltip:find("Tangled", 1, true))
onClick()
assert(toggled == "adam0/forges:panel")
print(
    "Forges: provider/CLI contracts, race isolation, scoped last-good recovery, auth/JSON/spawn errors, native surfaces, filtering, links and widget passed"
)
