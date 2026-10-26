--!nonstrict
local clock = 1700000000
local os = {
    date = os.date,
    time = function()
        return clock
    end,
}
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
local calls, lastPanel, panelRenders, lastCommand, lastLaunch, glyph, tooltip, toggled, wantsFrames
local nodeCreations = 0
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
local function calendarFixture(login, weekCount)
    local weeks, total = {}, 0
    for week = 1, weekCount or 2 do
        local days = {}
        for day = 0, 6 do
            local n = (week + day) % 5
            total += n
            table.insert(days, {
                date = os.date("!%Y-%m-%d", 1700352000 + ((week - 1) * 7 + day) * 86400),
                weekday = day,
                contributionCount = n,
                contributionLevel = ({
                    "NONE",
                    "FIRST_QUARTILE",
                    "SECOND_QUARTILE",
                    "THIRD_QUARTILE",
                    "FOURTH_QUARTILE",
                })[n + 1],
            })
        end
        table.insert(weeks, { contributionDays = days })
    end
    return {
        data = {
            viewer = {
                login = login or "octocat",
                contributionsCollection = {
                    contributionCalendar = { totalContributions = total, weeks = weeks },
                },
            },
        },
    }
end
local function githubResults(kind, title)
    return {
        items = {
            {
                number = kind == "pulls" and 1 or 2,
                title = title or "Task",
                state = "open",
                repository_url = "https://api.github.com/repos/octocat/example",
                html_url = "https://github.com/octocat/example/issues/1",
            },
        },
    }
end
local function respondGh(value, id, login)
    respond(value)
    assert(
        queue[1].argv[3] == "user",
        "REST results need a postflight account check before publication"
    )
    respond({ id = id or 1, login = login or "octocat" })
end
boot()
service()
assert(queue[1].argv[1] == "tg", "Tangled is the default")
respond({ authenticated = true, handle = "alice.test", did = "alice-did" })
assert(
    queue[1].argv[#queue[1].argv] == "alice-did",
    "Tangled resources are pinned to the verified account"
)
respond(tgRepo)
assert(snapshot().status == "ready" and snapshot().account == "alice.test" and #queue == 0)
assert(
    snapshot().repository == "alice.test/project" and #snapshot().pulls == 0,
    "Initial repository view must not prefetch unrelated work"
)
local before = calls
send({ op = "repository", repository = "alice.test/project" })
assert(
    calls == before + 1 and queue[1].argv[2] == "pr",
    "Inspect loads only PRs, not account/repositories/inbox"
)
respond(tgWork)
assert(
    #snapshot().pulls == 1
        and snapshot().pulls[1].url == "https://tangled.org/alice.test/project/pulls"
)
assert(snapshot().pulls[1].linkLabel == "Open repository pull requests")
send({ op = "view", view = "issues" })
respond({ items = {} })
assert(#snapshot().issues == 0)
before = calls
send({ op = "view", view = "issues" })
send({ op = "view", view = "pulls" })
send({ op = "view", view = "repositories" })
send({ op = "provider", provider = "tangled" })
onConfigChanged()
assert(calls == before, "Cached views, valid empty results and unchanged config issue no requests")
send({ op = "repository", repository = "--evil/repo" })
assert(calls == before)
send({ op = "repository", repository = "alice.test/.." })
assert(calls == before)
send({ op = "repository", repository = "alice.test/other;echo" })
assert(calls == before)
send({ op = "provider", provider = "github" })
assert(
    snapshot().provider == "github" and snapshot().account == "" and #snapshot().repositories == 0
)
respond({ id = 1, login = "octocat" })
assert(
    queue[1].argv[3] == "graphql",
    "GitHub restores the contribution calendar as its default view"
)
respond(calendarFixture())
assert(snapshot().status == "ready" and snapshot().contributions.total > 0 and #queue == 0)
send({ op = "view", view = "repositories" })
respondGh({ { full_name = "octocat/example", description = "Example" } })
send({ op = "view", view = "pulls" })
assert(queue[1].argv[3]:find("involves:@me", 1, true))
respondGh(githubResults("pulls"))
send({ op = "view", view = "issues" })
respondGh(githubResults("issues"))
send({ op = "view", view = "notifications" })
assert(
    queue[1].argv[3] == "notifications?all=true&per_page=50&page=1",
    "Inbox includes read and unread history"
)
local notices = {}
for index = 1, 50 do
    notices[index] = {
        id = tostring(index),
        unread = index % 2 == 1,
        subject = {
            title = "Notice " .. tostring(index),
            type = "Issue",
            url = "https://api.github.com/repos/o/r/issues/1",
        },
        repository = { full_name = "o/r" },
    }
end
respondGh(notices)
assert(#snapshot().notifications == 50 and snapshot().notification_has_more)
send({ op = "notifications_more" })
assert(queue[1].argv[3]:find("page=2", 1, true))
respondGh({ notices[50], { id = "51", subject = { title = "Older read notice" } } })
assert(
    #snapshot().notifications == 51
        and snapshot().notification_page == 2
        and not snapshot().notification_has_more
)
send({ op = "refresh" })
respond({ id = 1, login = "octocat" })
respond("network failure", 1)
assert(
    #snapshot().notifications == 51 and snapshot().notification_page == 2 and snapshot().stale,
    "Failed inbox refresh must preserve all previously loaded history and page metadata"
)
before = calls
send({ op = "provider", provider = "tangled" })
assert(snapshot().account == "alice.test")
send({ op = "provider", provider = "github" })
assert(snapshot().account == "octocat" and #snapshot().notifications == 51)
send({ op = "view", view = "repositories" })
send({ op = "view", view = "overview" })
send({ op = "view", view = "notifications" })
assert(calls == before, "Provider switches retain independent graph/repository/work/inbox caches")
-- Inactive responses may populate only their own cache, not whichever view is active.
send({ op = "repository", repository = "octocat/a" })
local oldA = assert(table.remove(queue, 1))
send({ op = "repository", repository = "octocat/b" })
local oldB = assert(table.remove(queue, 1))
send({ op = "provider", provider = "tangled" })
oldA.callback({ exitCode = 0, stdout = githubResults("pulls", "A") })
oldB.callback({ exitCode = 0, stdout = githubResults("pulls", "B") })
respond({ id = 1, login = "octocat" })
respond({ id = 1, login = "octocat" })
assert(snapshot().provider == "tangled" and snapshot().account == "alice.test")
before = calls
send({ op = "provider", provider = "github" })
assert(snapshot().pulls[1].title == "B")
send({ op = "repository", repository = "octocat/a" })
assert(snapshot().pulls[1].title == "A")
assert(
    calls == before and #snapshot().notifications == 51,
    "Repository cache survives A -> B -> A without refetching anything"
)
-- Confirmed account change invalidates the old account epoch, including pending resources.
send({ op = "view", view = "issues" })
local oldIssue = assert(table.remove(queue, 1))
send({ op = "refresh" })
respond({ id = 2, login = "other-account" })
oldIssue.callback({ exitCode = 0, stdout = githubResults("issues", "Private old issue") })
respondGh({ items = {} }, 2, "other-account")
assert(
    snapshot().account == "other-account"
        and #snapshot().issues == 0
        and #snapshot().repositories == 0
)
assert(
    #snapshot().notifications == 0
        and snapshot().contributions == nil
        and snapshot().repository == ""
)
send({ op = "view", view = "overview" })
local oldGraph = assert(table.remove(queue, 1))
send({ op = "refresh" })
respond("", 1, "To get started with GitHub CLI, please run: gh auth login")
oldGraph.callback({ exitCode = 0, stdout = calendarFixture("other-account") })
assert(
    snapshot().status == "auth_error"
        and snapshot().account == ""
        and snapshot().contributions == nil,
    "Logout clears private caches and prevents late graph callbacks from repopulating them"
)
-- Loading older results after a CLI account switch must never append B data to A.
boot({ provider = "github" })
service()
respond({ id = 1, login = "octocat" })
respond(calendarFixture())
send({ op = "view", view = "notifications" })
respondGh(notices)
send({ op = "notifications_more" })
respond({ { id = "private-B", subject = { title = "Account B only" } } })
assert(
    snapshot().account == "octocat" and #snapshot().notifications == 50,
    "Unverified REST results must not be displayed"
)
respond({ id = 2, login = "other-account" })
assert(
    snapshot().account == "other-account"
        and #snapshot().notifications == 0
        and snapshot().contributions == nil
)
assert(queue[1].argv[3] == "notifications?all=true&per_page=50&page=1")
respondGh({ { id = "B", subject = { title = "B first page" } } }, 2, "other-account")
assert(
    #snapshot().notifications == 1
        and snapshot().notifications[1].id == "B"
        and snapshot().notification_page == 1
)
-- Failure freshness is per resource and never advances the last-success timestamp.
boot()
service()
respond({ authenticated = true, handle = "alice.test" })
respond(tgRepo)
send({ op = "repository", repository = "alice.test/project" })
respond(tgWork)
local lastSuccess = snapshot().updated_at
send({ op = "refresh" })
respond("unavailable", 1)
assert(snapshot().status == "partial" and snapshot().stale and #snapshot().pulls == 1)
assert(
    snapshot().updated_at == lastSuccess and not snapshot().errors.account:find("secret", 1, true)
)
send({ op = "view", view = "issues" })
assert(
    queue[1].argv[2] == "issue",
    "A transient profile refresh failure must not block other pinned-account views"
)
respond({ items = {} })
send({ op = "view", view = "pulls" })
send({ op = "refresh" })
respond({ authenticated = true, handle = "alice.test" })
assert(
    #queue == 1 and queue[1].argv[2] == "pr",
    "Manual refresh targets the current resource, not every list"
)
respond("bad-json")
assert(snapshot().status == "partial" and snapshot().stale and #snapshot().pulls == 1)
before = calls
send({ op = "view", view = "repositories" })
assert(calls == before and snapshot().status == "ready")
send({ op = "view", view = "pulls" })
assert(calls == before and snapshot().status == "partial")
clock += 901
update()
assert(queue[1].argv[2] == "auth")
respond({ authenticated = true, handle = "alice.test" })
respond({ items = {} })
assert(
    snapshot().status == "ready" and #snapshot().pulls == 0 and snapshot().updated_at > lastSuccess
)
before = calls
send({ op = "view", view = "pulls" })
assert(calls == before, "An empty successful result is a cache hit")
send({ op = "refresh" })
before = calls
send({ op = "refresh" })
assert(calls == before, "In-flight auth and resource loads are coalesced")
respond({ authenticated = false })
assert(snapshot().status == "auth_error" and snapshot().account == "" and #snapshot().pulls == 0)
boot()
exists = false
service()
assert(snapshot().status == "missing_cli" and #queue == 0)
boot()
failStart = true
service()
assert(snapshot().status == "partial" and #queue == 0)
boot()
service()
respond("bad-json")
assert(snapshot().status == "partial" and snapshot().account == "")
boot()
service()
respond({ authenticated = true, handle = "new.test" })
respond({ items = {} })
assert(snapshot().status == "ready" and snapshot().repository == "")
send({ op = "repository", repository = "tangled.org/core" })
assert(queue[1].argv[4] == "tangled.org/core", "External repository remains a literal argv element")
respond(tgWork)
-- Retain at most eight repository scopes, and report temporary in-flight backpressure.
for index = 1, 12 do
    send({ op = "repository", repository = "alice.test/repo" .. tostring(index) })
end
assert(
    #queue <= 8 and snapshot().errors.pulls,
    "Bound pending repository caches instead of growing indefinitely"
)
while #queue > 0 do
    respond(tgWork)
end
send({ op = "refresh" })
respond({ authenticated = true, handle = "new.test" })
respond(tgWork)
assert(snapshot().status == "ready" and snapshot().repository == "alice.test/repo12")
local many = { items = {} }
for index = 1, 100 do
    many.items[index] = tgWork.items[1]
end
assert(#Tangled.normalizeWork(many, "a/b", "issues") == 30)
assert(Tangled.normalizeWork({}, "a/b", "issues") == nil)
assert(Data.work({}) == nil and Tangled.normalizeProfile({ authenticated = false }) == nil)
assert(GitHub.work("issues", "a/b")[3]:find("repo:a/b", 1, true))
local graphData = assert(Data.contributions(calendarFixture("octocat", 54)))
assert(#graphData.weeks == 54 and #graphData.weeks[1].days == 7)
local invalidGraph = calendarFixture()
invalidGraph.errors = { { message = "denied" } }
assert(
    Data.contributions(invalidGraph) == nil,
    "Exit-zero GraphQL errors must not become an empty calendar"
)
invalidGraph = calendarFixture()
invalidGraph.data.viewer.contributionsCollection.contributionCalendar.totalContributions = 0 / 0
assert(Data.contributions(invalidGraph) == nil)
invalidGraph = calendarFixture()
invalidGraph.data.viewer.contributionsCollection.contributionCalendar.weeks[1].contributionDays[2].weekday =
    0
assert(Data.contributions(invalidGraph) == nil, "Duplicate calendar slots must be rejected")
local partialWeek = calendarFixture()
table.remove(
    partialWeek.data.viewer.contributionsCollection.contributionCalendar.weeks[1].contributionDays,
    1
)
local partialData = assert(Data.contributions(partialWeek))
assert(partialData.weeks[1].days[1] == false and partialData.weeks[1].days[2] ~= false)

local ui = setmetatable({}, {
    __index = function(_, kind)
        return function(props, children)
            nodeCreations += 1
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
    setNeedsFrameTick = function(value)
        wantsFrames = value
    end,
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
-- Inbox filters operate on the same fetched page and never touch the service.
local inboxSnapshot = {
    provider = "github",
    account = "octocat",
    view = "notifications",
    status = "ready",
    repository = "",
    notifications = Data.notifications(notices),
    errors = {},
    loading = {},
    notification_has_more = true,
}
noctalia.state.set("forges.snapshot", inboxSnapshot)
assert(find("column", function(props)
    return props.key == "github-notifications-o/r-1"
end))
assert(find("column", function(props)
    return props.key == "github-notifications-o/r-2"
end))
local filterCalls = calls
assert(find("button", function(props)
    return props.text == "Read"
end)).props.onClick()
assert(not find("column", function(props)
    return props.key == "github-notifications-o/r-1"
end))
assert(find("column", function(props)
    return props.key == "github-notifications-o/r-2"
end))
assert(find("button", function(props)
    return props.text == "Unread"
end)).props.onClick()
assert(find("column", function(props)
    return props.key == "github-notifications-o/r-1"
end))
assert(not find("column", function(props)
    return props.key == "github-notifications-o/r-2"
end))
assert(find("button", function(props)
    return props.text == "All"
end)).props.onClick()
assert(calls == filterCalls, "All/read/unread filtering must issue zero network requests")
assert(not find("column", function(props)
    return props.key == "github-notifications-o/r-21"
end), "Only 20 matching inbox rows are rendered at once")
assert(find("button", function(props)
    return props.key == "inbox-next"
end)).props.onClick()
assert(find("column", function(props)
    return props.key == "github-notifications-o/r-21"
end))
assert(not find("column", function(props)
    return props.key == "github-notifications-o/r-1"
end))
assert(calls == filterCalls, "Paging through loaded history must issue zero requests")
assert(find("button", function(props)
    return props.text == "Load older notifications"
end)).props.onClick()
assert(lastCommand.op == "notifications_more")
-- A complete 54-week calendar is built off the render callback in bounded chunks.
local graphSnapshot = {
    provider = "github",
    account = "octocat",
    view = "overview",
    status = "ready",
    contributions = graphData,
    versions = { contributions = 1 },
    errors = {},
    loading = {},
}
settings["shell.corner_radius_scale"] = 0
noctalia.state.set("forges.snapshot", graphSnapshot)
assert(wantsFrames and not find("row", function(props)
    return props.key == "contribution-grid"
end))
for frame = 1, 14 do
    local created = nodeCreations
    onFrameTick()
    assert(nodeCreations - created < 100, "Graph preparation must stay bounded per frame")
end
local grid = assert(find("row", function(props)
    return props.key == "contribution-grid"
end))
assert(
    #grid.children == 54 and not wantsFrames,
    "Show the entire year rather than truncating graph weeks"
)
local cellCount, dayCell = 0, nil
walk(grid, function(node)
    if node.kind == "box" and node.props.key then
        cellCount += 1
        dayCell = node
        assert(node.props.radius == 0 and node.props.tooltip:find("contributions", 1, true))
    end
end)
assert(cellCount == 378, "All bounded source calendar days must remain visible")
dayCell.props.onClick()
assert(find("label", function(props)
    return props.text:find("contributions", 1, true) ~= nil
end))
local oldGrid = grid
noctalia.state.set("forges.snapshot", graphSnapshot)
local reusedGrid = find("row", function(props)
    return props.key == "contribution-grid"
end)
assert(
    reusedGrid == oldGrid and not wantsFrames,
    "Unrelated snapshot publications must reuse the prepared calendar"
)
settings["shell.corner_radius_scale"] = 1.5
onConfigChanged()
assert(wantsFrames)
onFrameTick()
onClose()
assert(not wantsFrames)
onOpen()
for _ = 1, 14 do
    onFrameTick()
end
grid = assert(find("row", function(props)
    return props.key == "contribution-grid"
end))
assert(grid.children[1].children[1].props.radius == 3)
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
values["forges.snapshot"] = { provider = "tangled", account = "alice.test", status = "ready" }
widgetEntry()
assert(glyph == "git-branch" and tooltip:find("Tangled", 1, true))
onClick()
assert(toggled == "adam0/forges:panel")
print(
    "Forges: independent provider/resource caches, zero-request switches and inbox filters, paged read/unread history, complete staged graph, account invalidation, race/error recovery and native surfaces passed"
)
