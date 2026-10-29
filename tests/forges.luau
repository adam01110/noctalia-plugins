--!nonstrict
local clock = 1700000000
local systemTime = os.time
local os = {
    date = os.date,
    time = function(value)
        return value and systemTime(value) or clock
    end,
}
local Activity = (function()
    -- ACTIVITY_SOURCE
end)()
local GitHub = (function()
    -- GITHUB_SOURCE
end)()
local Data = (function()
    -- DATA_SOURCE
end)()
local Tangled = (function()
    -- TANGLED_SOURCE
end)()

local GitLab = (function()
    -- GITLAB_SOURCE
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
local config, settings, values, watches, queue, exists, failStart, missingCommands
local calls, lastPanel, panelRenders, lastCommand, lastLaunch, glyph, tooltip, toggled, wantsFrames
local secondTicks = false
local nodeCreations = 0
local imageFiles, imageWrites, failImageWrite, deferActivity = {}, 0, false, false
local noctalia = {
    pluginDataDir = function()
        return "/plugin-data/forges"
    end,
    mkdirAll = function()
        return true
    end,
    writeFile = function(path, content)
        if failImageWrite then
            return false, "disk full"
        end
        imageFiles[path] = content
        imageWrites += 1
        return true
    end,
    renameFile = function(source, target)
        if not imageFiles[source] then
            return false
        end
        imageFiles[target], imageFiles[source] = imageFiles[source], nil
        return true
    end,
    removeFile = function(path)
        imageFiles[path] = nil
        return true
    end,
    getColor = function(role)
        return settings["color." .. role]
            or ({
                surface = "#202124",
                surface_variant = "#303134",
                on_surface = "#e8eaed",
                outline = "#777777",
                primary = "#a8c7fa",
                error = "#f28b82",
            })[role]
    end,
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
    commandExists = function(name)
        return exists and not missingCommands[name]
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
        if argv[1] == "curl" then
            assert(
                argv[#argv]:sub(1, 29) == "https://api.tangled.org/xrpc/",
                "Only structured public Tangled API requests are allowed"
            )
        end
        -- Legacy scenarios stub the optional typed-count capability as unsupported.
        -- Dedicated tests below defer it to exercise success, partial data and identity races.
        if
            callback
            and argv[1] == "glab"
            and argv[7]
            and argv[7]:find("query ForgesActivity", 1, true)
            and not deferActivity
        then
            callback({ exitCode = 0, stdout = { errors = { { message = "unsupported" } } } })
            return true
        end
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
local function boot(options, publicData)
    config = options or {}
    settings, values, watches, queue, missingCommands = {}, {}, {}, {}, {}
    exists, failStart, calls = true, false, 0
    imageFiles, imageWrites, failImageWrite, deferActivity = {}, 0, false, false
    missingCommands.curl = not publicData
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
assert(GitLab.instance(nil) == "https://gitlab.com")
assert(GitLab.instance("https://GitLab.school.edu/") == "https://gitlab.school.edu")
for _, url in ipairs({
    "http://school.edu",
    "https://school.edu/path",
    "https://user@school.edu",
    "https://school.edu?token=x",
    "https://school.edu/#x",
    "--hostname",
}) do
    assert(GitLab.instance(url) == nil)
end
assert(GitLab.validRepository("school/course/project"))
assert(not GitLab.validRepository("school/../project"))
assert(not GitLab.validRepository("school//project"))
assert(not GitLab.validRepository("school/project;echo"))
assert(
    GitLab.work("gitlab.school.edu", "pulls", "school/course/project")[3]
        == "projects/school%2Fcourse%2Fproject/merge_requests?scope=all&state=opened&order_by=updated_at&per_page=30"
)
local function unsupportedCalendar()
    assert(queue[1].argv[3] == "graphql" and queue[1].argv[7]:find("contributionCalendar", 1, true))
    respond({ errors = { { message = "Field contributionCalendar does not exist" } } })
end
local glProfile = { id = 42, username = "student" }
local glRepos = {
    {
        path_with_namespace = "school/course/project",
        web_url = "https://gitlab.school.edu/school/course/project",
    },
}
boot({ provider = "gitlab", gitlab_url = "https://gitlab.school.edu/" })
service()
assert(queue[1].argv[1] == "glab" and queue[1].argv[5] == "gitlab.school.edu")
respond(glProfile)
unsupportedCalendar()
respond(glRepos)
assert(snapshot().repositories[1] == nil)
respond(glProfile)
assert(snapshot().repositories[1].name == "school/course/project")
assert(snapshot().base_url == "https://gitlab.school.edu")
send({ op = "repository", repository = "school/course/project" })
assert(queue[1].argv[3]:find("school%%2Fcourse%%2Fproject"))
respond({
    {
        iid = 3,
        title = "Assignment",
        author = { username = "student" },
        web_url = "https://gitlab.school.edu/school/course/project/-/merge_requests/3",
    },
})
respond(glProfile)
assert(snapshot().pulls[1].id == "3")
send({ op = "profile", provider = "gitlab" })
assert(lastLaunch[2] == "https://gitlab.school.edu/student")
send({ op = "refresh" })
local late = table.remove(queue, 1)
config.gitlab_url = "https://other.school.edu"
onConfigChanged()
assert(snapshot().account == "" and #snapshot().repositories == 0 and #snapshot().pulls == 0)
late.callback({ exitCode = 0, stdout = glProfile })
assert(snapshot().account == "")
assert(queue[1].argv[5] == "other.school.edu")
respond(glProfile)
unsupportedCalendar()
respond({})
respond(glProfile)
assert(snapshot().status == "ready")
boot({ provider = "gitlab", gitlab_url = "https://school.edu/path" })
service()
assert(#queue == 0 and snapshot().errors.account:find("HTTPS origin"))
boot({ provider = "gitlab" })
service()
respond({}, 1, "401 Unauthorized")
assert(snapshot().status == "auth_error" and snapshot().errors.account:find("glab auth login"))

boot({ provider = "gitlab" })
service()
respond(glProfile)
unsupportedCalendar()
respond(glRepos)
respond({ id = 99, username = "other" })
assert(snapshot().account == "other" and #snapshot().repositories == 0)
unsupportedCalendar()
respond({})
respond({ id = 99, username = "other" })
assert(snapshot().status == "ready")
send({ op = "repository", repository = "school/course/project" })
respond({})
respond({ id = 99, username = "other" })
send({ op = "view", view = "issues" })
assert(queue[1].argv[3]:find("/issues?", 1, true))
respond({ { iid = 7, title = "Question" } })
respond({ id = 99, username = "other" })
assert(snapshot().issues[1].id == "7")
missingCommands.glab = true
send({ op = "refresh" })
assert(snapshot().status == "missing_cli" and snapshot().errors.account:find("glab"))

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
    local raw = {
        data = {
            viewer = {
                login = login or "octocat",
                contributionsCollection = {
                    contributionCalendar = { totalContributions = total, weeks = weeks },
                },
            },
        },
    }
    for i, month in ipairs(Activity.months()) do
        raw.data.viewer["activity" .. tostring(i)] = {
            startedAt = month.date .. "-01T00:00:00Z",
            totalCommitContributions = i,
            totalPullRequestContributions = i % 2,
            totalIssueContributions = 0,
            totalRepositoryContributions = 0,
        }
    end
    return raw
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
local today = os.date("!%Y-%m-%d", clock)
local function glCalendar(login, count)
    return {
        data = {
            currentUser = {
                username = login or "student",
                contributionCalendar = {
                    totalCount = count or 4,
                    utcOffset = 0,
                    days = { { date = today, count = count or 4 } },
                },
            },
        },
    }
end
local function glActivityFixture(login)
    local raw = { data = { currentUser = { username = login or "student" } } }
    for i = 1, 6 do
        raw.data.currentUser["pulls" .. tostring(i)] = { count = i }
        raw.data["issues" .. tostring(i)] = { count = i == 6 and 10001 or 0 }
    end
    return raw
end
local typedGitLab = assert(GitLab.normalizeActivity(glActivityFixture(), "student"))
assert(typedGitLab.months[6].values.pulls == 6 and typedGitLab.months[6].values.issues == 10001)
assert(typedGitLab.months[6].lowerBounds.issues and not typedGitLab.months[6].lowerBounds.pulls)
assert(typedGitLab.months[6].values.commits == nil and typedGitLab.months[6].values.repos == nil)
assert(not GitLab.normalizeActivity(glActivityFixture("other"), "student"))
local invalidTyped = glActivityFixture()
invalidTyped.data.issues6.count = 10002
assert(not GitLab.normalizeActivity(invalidTyped, "student"))
invalidTyped = glActivityFixture()
invalidTyped.data.currentUser.pulls1.count = -1
assert(not GitLab.normalizeActivity(invalidTyped, "student"))
local typedArgv = GitLab.activity("gitlab.school.edu", "student")
assert(typedArgv[7]:find("query ForgesActivity", 1, true) and typedArgv[9] == "login=student")
assert(typedArgv[7]:find("count(limit: 10000)", 1, true))
local function glTodoPage(nodes, more, cursor)
    return {
        data = {
            currentUser = {
                username = "student",
                todos = {
                    nodes = nodes,
                    pageInfo = { hasNextPage = more or false, endCursor = cursor },
                },
            },
        },
    }
end
local todoPending = {
    id = "gid://gitlab/Todo/1",
    body = "Review assignment",
    state = "pending",
    createdAt = today,
    targetUrl = "https://gitlab.com/school/course/project/-/merge_requests/2",
    project = { fullPath = "school/course/project" },
    author = { username = "teacher" },
}
local todoDone =
    { id = "gid://gitlab/Todo/2", body = "Submitted", state = "done", createdAt = today }
local todoData = GitLab.normalizeNotifications(
    glTodoPage({ todoPending, todoDone }, true, "cursor-1"),
    "student"
)
assert(
    #todoData.rows == 2 and todoData.rows[1].state == "pending" and todoData.rows[2].state == "done"
)
assert(todoData.has_more and todoData.cursor == "cursor-1")
assert(GitLab.normalizeNotifications(glTodoPage({}, true), "student") == nil)
assert(GitLab.normalizeNotifications(glTodoPage({ todoPending }), "other") == nil)
assert(GitLab.normalizeNotifications({ errors = { { message = "denied" } } }, "student") == nil)
assert(GitLab.notifications("gitlab.school.edu", "cursor-1")[9] == "cursor=cursor-1")
local glItem = {
    iid = "2",
    title = "Review",
    state = "opened",
    updatedAt = today,
    webUrl = "https://gitlab.com/school/course/project/-/merge_requests/2",
    project = { fullPath = "school/course/project" },
}
local allMergeRequests = {
    data = {
        currentUser = {
            username = "student",
            authored = { nodes = { glItem } },
            assigned = { nodes = { glItem } },
            reviewing = { nodes = {} },
        },
    },
}
local allIssues = {
    data = {
        currentUser = { username = "student" },
        authored = {
            nodes = {
                {
                    iid = "3",
                    title = "Issue",
                    state = "opened",
                    updatedAt = today,
                    webUrl = "https://gitlab.com/school/course/project/-/issues/3",
                },
            },
        },
        assigned = { nodes = {} },
    },
}
assert(#GitLab.normalizeWork(allMergeRequests, "", "student") == 1)
assert(GitLab.normalizeWork(allIssues, "", "student")[1].repository == "school/course/project")
assert(GitLab.normalizeWork(allMergeRequests, "", "other") == nil)
assert(GitLab.normalizeWork({ errors = { {} } }, "", "student") == nil)
assert(
    GitLab.work("gitlab.com", "pulls", "", "student")[7]
        :find("reviewRequestedMergeRequests", 1, true)
)
assert(GitLab.work("gitlab.com", "issues", "", "student")[9] == "login=student")
local normalCalendar = Data.dailyContributions({ [today] = 4 }, "student")
assert(
    normalCalendar.today == 4 and normalCalendar.total == 4 and normalCalendar.currentStreak == 1
)
assert(Data.dailyContributions({ ["2023-02-30"] = 1 }, "student") == nil)
assert(Data.dailyContributions({ [today] = -1 }, "student") == nil)
assert(Data.dailyContributions({ [today] = math.huge }, "student") == nil)
local savedClock = clock
clock = systemTime({ year = 2024, month = 1, day = 1, hour = 23, min = 30 })
local timezoneCalendar = Data.dailyContributions({ ["2024-01-02"] = 5 }, "student", 3600)
assert(
    timezoneCalendar.today == 5
        and timezoneCalendar.currentStreak == 1
        and timezoneCalendar.lastDate == "2024-01-02"
)
local timezoneStreak = Data.dailyContributions({ ["2024-01-01"] = 3 }, "student", 3600)
assert(timezoneStreak.today == 0 and timezoneStreak.currentStreak == 1)
clock = savedClock
local tgActivity = {
    months = { { start = today:sub(1, 7) .. "-01T00:00:00.000000Z", commits = 4 } },
    truncated = false,
}
local tgMonthly = assert(Tangled.normalizeContributions(tgActivity, "alice.test"))
assert(
    tgMonthly.granularity == "month"
        and #tgMonthly.months == 12
        and tgMonthly.total == 4
        and tgMonthly.peak == 4
)
assert(tgMonthly.months[12].date == today:sub(1, 7) and tgMonthly.months[12].count == 4)
assert(
    tgMonthly.months[1].count == 0
        and not tgMonthly.weeks
        and not tgMonthly.today
        and not tgMonthly.currentStreak
)
assert(Tangled.normalizeContributions({ months = {}, truncated = false }, "alice.test").total == 0)
assert(Tangled.normalizeContributions({ months = {}, truncated = true }, "alice.test").total == 0)
assert(Tangled.normalizeContributions({ months = {} }, "alice.test") == nil)
for _, n in ipairs({ -1, 0.5, math.huge, 0 / 0, "4", 1000000001 }) do
    local invalid = copy(tgActivity)
    invalid.months[1].commits = n
    assert(Tangled.normalizeContributions(invalid, "alice.test") == nil)
end
for _, start in ipairs({
    "2023-13-01T00:00:00Z",
    "9999-01-01T00:00:00Z",
    today:sub(1, 7) .. "-02T00:00:00Z",
    today:sub(1, 7) .. "-01T00:00:00+00:00",
}) do
    local invalid = copy(tgActivity)
    invalid.months[1].start = start
    assert(Tangled.normalizeContributions(invalid, "alice.test") == nil)
end
local truncatedLists = copy(tgActivity)
truncatedLists.truncated = true
assert(Tangled.normalizeContributions(truncatedLists, "alice.test").total == 4)
local unorderedMonths = copy(tgActivity)
table.insert(
    unorderedMonths.months,
    { start = tgMonthly.months[11].date .. "-01T00:00:00Z", commits = 2 }
)
local orderedMonths = assert(Tangled.normalizeContributions(unorderedMonths, "alice.test"))
assert(
    orderedMonths.total == 6
        and orderedMonths.months[11].count == 2
        and orderedMonths.months[12].count == 4
)
local duplicateMonths = copy(tgActivity)
table.insert(duplicateMonths.months, copy(duplicateMonths.months[1]))
assert(Tangled.normalizeContributions(duplicateMonths, "alice.test") == nil)
local monthArgv = Tangled.contributions("did:plc:alice")
assert(
    monthArgv[#monthArgv]
        == "https://api.tangled.org/xrpc/org.tangled.actor.getProfileActivity?actor=did%3Aplc%3Aalice&months=12"
)
local tgDid = "did:plc:alice"
local tgAuthored = {
    items = {
        {
            uri = "at://" .. tgDid .. "/sh.tangled.repo.issue/task1",
            state = "open",
            value = { title = "Public question", repo = "did:plc:project", createdAt = today },
        },
    },
}
assert(
    Tangled.normalizeAuthoredWork(tgAuthored, tgDid, "alice.test", "issues")[1].repoDid
        == "did:plc:project"
)
assert(Tangled.normalizeAuthoredWork(tgAuthored, "did:plc:other", "other.test", "issues") == nil)
assert(Tangled.normalizeAuthoredWork(tgAuthored, tgDid, "alice.test", "pulls") == nil)
local tgPulls = copy(tgAuthored)
tgPulls.items[1].uri = "at://" .. tgDid .. "/sh.tangled.repo.pull/task1"
tgPulls.items[1].value.repo = nil
tgPulls.items[1].value.target = { repo = "did:plc:destination" }
tgPulls.items[1].value.source = { repo = "did:plc:source" }
assert(
    Tangled.normalizeAuthoredWork(tgPulls, tgDid, "alice.test", "pulls")[1].repoDid
        == "did:plc:destination"
)
tgPulls.items[1].state = "merged"
assert(#Tangled.normalizeAuthoredWork(tgPulls, tgDid, "alice.test", "pulls") == 0)
local closedIssue = copy(tgAuthored)
closedIssue.items[1].state = "closed"
assert(#Tangled.normalizeAuthoredWork(closedIssue, tgDid, "alice.test", "issues") == 0)
assert(
    Tangled.normalizeRepositoryInfo({ uri = "at://did:plc:owner/sh.tangled.repo/project" }).url
        == "https://tangled.org/did:plc:owner/project"
)
assert(Tangled.normalizeRepositoryInfo({ uri = "https://evil.invalid/" }) == nil)
boot({ provider = "gitlab" })
service()
respond(glProfile)
respond(glCalendar())
respond(glRepos)
respond(glProfile)
respond(glProfile)
assert(snapshot().contributions.today == 4 and #queue == 0)
send({ op = "view", view = "notifications" })
assert(queue[1].argv[7]:find("state: [pending, done]", 1, true))
respond(glTodoPage({ todoPending }, true, "cursor-1"))
respond(glProfile)
assert(snapshot().notifications[1].state == "pending" and snapshot().notification_has_more)
send({ op = "notifications_more" })
assert(queue[1].argv[9] == "cursor=cursor-1")
respond({ errors = { { message = "temporary failure" } } })
assert(
    snapshot().notification_page == 1
        and snapshot().notification_has_more
        and #snapshot().notifications == 1
)
send({ op = "notifications_more" })
assert(queue[1].argv[9] == "cursor=cursor-1")
respond(glTodoPage({ todoPending, todoDone }))
respond(glProfile)
assert(
    #snapshot().notifications == 2
        and snapshot().notification_page == 2
        and not snapshot().notification_has_more
)
send({ op = "view", view = "pulls" })
assert(queue[1].argv[3] == "graphql")
respond(allMergeRequests)
respond(glProfile)
assert(#snapshot().pulls == 1 and snapshot().repository == "")
send({ op = "view", view = "issues" })
respond(allIssues)
respond(glProfile)
assert(snapshot().issues[1].repository == "school/course/project")
local cachedCalls = calls
send({ op = "view", view = "notifications" })
send({ op = "view", view = "pulls" })
assert(calls == cachedCalls, "GitLab calendars, inbox and global work retain independent caches")
boot({}, true)
service()
respond({ authenticated = true, handle = "alice.test", did = tgDid })
assert(#queue == 2 and queue[1].argv[1] == "curl")
respond(tgActivity)
respond(tgRepo)
assert(
    snapshot().contributions.total == 4
        and snapshot().capabilities.contributions == true
        and snapshot().repository == ""
)
send({ op = "view", view = "issues" })
assert(queue[1].argv[#queue[1].argv]:find("listIssuesBy", 1, true))
respond(tgAuthored)
assert(snapshot().issues[1].repoDid == "did:plc:project")
assert(queue[1].argv[#queue[1].argv]:find("getRepoByRepoDid", 1, true))
respond({ uri = "at://did:plc:owner/sh.tangled.repo/project" })
assert(snapshot().issues[1].repository == "did:plc:owner/project")
assert(snapshot().issues[1].url == "https://tangled.org/did:plc:owner/project/issues")
local tgCached = calls
send({ op = "view", view = "repositories" })
send({ op = "view", view = "issues" })
assert(calls == tgCached, "Public Tangled work/repository metadata are cached")
send({ op = "view", view = "pulls" })
respond(tgAuthored)
assert(
    #snapshot().pulls == 0 and snapshot().errors.pulls,
    "Reject a mismatched authored collection, without fallback normalization"
)
send({ op = "view", view = "issues" })
send({ op = "refresh" })
respond({ authenticated = true, handle = "alice.test", did = tgDid })
respond(tgActivity)
local nextWork = copy(tgAuthored)
nextWork.items[1].value.repo = "did:plc:second"
respond(nextWork)
local pendingDetail = assert(table.remove(queue, 1))
send({ op = "refresh" })
respond({ authenticated = true, handle = "alice.test", did = tgDid })
respond(tgActivity)
nextWork.items[1].value.title = "Updated during resolution"
respond(nextWork)
pendingDetail.callback({
    exitCode = 0,
    stdout = { uri = "at://did:plc:owner/sh.tangled.repo/second" },
})
assert(
    snapshot().issues[1].title == "Updated during resolution"
        and snapshot().issues[1].repository == "did:plc:owner/second"
)
assert(
    #queue == 0,
    "A refreshed resolution chain must resume after an older detail request completes"
)
local publicCalls = calls
send({ op = "view", view = "notifications" })
assert(
    calls == publicCalls and snapshot().view == "issues",
    "Tangled must not expose an invented inbox API"
)
local streakCounts, levelDates = {}, {}
for index, n in ipairs({ 10, 6, 3, 0, 2, 0 }) do
    local date = os.date("!%Y-%m-%d", clock + (index - 6) * 86400)
    streakCounts[date], levelDates[index] = n, date
end
local streakGraph = assert(Data.dailyContributions(streakCounts, "alice.test", 0))
assert(
    streakGraph.total == 21
        and streakGraph.today == 0
        and streakGraph.currentStreak == 1
        and streakGraph.bestStreak == 3
)
local expectedLevels = { 4, 3, 2, 0, 1, 0 }
for _, week in ipairs(streakGraph.weeks) do
    for _, day in ipairs(week.days) do
        if day then
            local index = table.find(levelDates, day.date)
            if index then
                assert(day.level == expectedLevels[index])
            else
                assert(day.count == 0 and day.level == 0)
            end
        end
    end
end
streakCounts[today] = 4
streakGraph = assert(Data.dailyContributions(streakCounts, "alice.test", 0))
assert(
    streakGraph.total == 25
        and streakGraph.today == 4
        and streakGraph.currentStreak == 2
        and streakGraph.bestStreak == 3
)
boot({}, true)
service()
respond({ authenticated = true, handle = "alice.test", did = tgDid })
assert(
    #queue == 2
        and queue[1].argv[#queue[1].argv]:find("org.tangled.actor.getProfileActivity", 1, true),
    "Tangled must use structured monthly activity, never profile HTML"
)
respond(tgActivity)
respond(tgRepo)
assert(snapshot().status == "ready" and snapshot().capabilities.contributions == true)
assert(
    snapshot().contributions.total == 4
        and not snapshot().errors.contributions
        and not snapshot().loading.contributions
)
assert(
    not watches["forges.calendar_step"],
    "No calendar parser continuation may survive the rewrite"
)
send({ op = "profile", provider = "tangled" })
assert(
    lastLaunch[1] == "xdg-open"
        and lastLaunch[2] == "https://tangled.org/alice.test"
        and #queue == 0
)
send({ op = "view", view = "issues" })
respond("<html>New appview</html>")
assert(
    snapshot().errors.issues == "Invalid JSON returned by forge CLI."
        and not snapshot().errors.contributions
)
send({ op = "refresh" })
respond({ authenticated = true, handle = "alice.test", did = tgDid })
respond(tgActivity)
assert(#queue == 1 and queue[1].argv[#queue[1].argv]:find("listIssuesBy", 1, true))
respond({ items = {} })
assert(snapshot().status == "ready" and #snapshot().issues == 0 and #queue == 0)
local monthlyVersion = snapshot().versions.contributions
send({ op = "refresh" })
respond({ authenticated = true, handle = "alice.test", did = tgDid })
respond(nil, 22)
respond({ items = {} })
assert(
    snapshot().contributions.total == 4
        and snapshot().versions.contributions == monthlyVersion
        and snapshot().errors.contributions,
    "Failed calendar refresh must retain the previous valid monthly data"
)
send({ op = "refresh" })
respond({ authenticated = true, handle = "alice.test", did = tgDid })
local lateMonthly = assert(table.remove(queue, 1))
respond({ items = {} })
send({ op = "refresh" })
respond({ authenticated = false })
lateMonthly.callback({ exitCode = 0, stdout = tgActivity })
assert(
    snapshot().account == "" and not snapshot().contributions,
    "Reject monthly responses after logout"
)
-- Typed GitLab activity succeeds even when the experimental calendar is unsupported.
boot({ provider = "gitlab" })
deferActivity = true
service()
respond(glProfile)
assert(queue[1].argv[7]:find("query ForgesActivity", 1, true))
respond(glActivityFixture())
unsupportedCalendar()
respond(glRepos)
respond(glProfile) -- Postflight identity for typed activity.
respond(glProfile) -- Postflight identity for repositories.
assert(#queue == 0 and snapshot().contributions.activity.months[6].values.pulls == 6)
assert(not snapshot().errors.contributions and not snapshot().contributions.weeks)
send({ op = "view", view = "overview" })
assert(
    snapshot().status == "ready" and snapshot().updated_at ~= nil,
    "Overview freshness follows the displayed typed chart"
)
send({ op = "view", view = "repositories" })
local typedVersion = snapshot().versions.activity
local typedCalls = calls
send({ op = "view", view = "repositories" })
assert(calls == typedCalls, "Typed activity has its own freshness cache")
send({ op = "refresh" })
respond(glProfile)
local lateTyped = assert(table.remove(queue, 1))
unsupportedCalendar()
respond(glRepos)
respond(glProfile)
send({ op = "refresh" })
respond({ authenticated = false })
lateTyped.callback({ exitCode = 0, stdout = glActivityFixture() })
assert(
    not snapshot().contributions and snapshot().account == "",
    "Logout rejects late typed activity responses"
)
-- Failed typed refresh retains the last good breakdown, not fabricated zeroes.
boot({ provider = "gitlab" })
deferActivity = true
service()
respond(glProfile)
respond(glActivityFixture())
unsupportedCalendar()
respond(glRepos)
respond(glProfile)
respond(glProfile)
typedVersion = snapshot().versions.activity
send({ op = "refresh" })
respond(glProfile)
respond({ errors = { { message = "unsupported" } } })
unsupportedCalendar()
respond(glRepos)
respond(glProfile)
assert(
    snapshot().versions.activity == typedVersion
        and snapshot().contributions.activity.months[6].values.pulls == 6
)
assert(snapshot().errors.contributions and #queue == 0)
send({ op = "view", view = "overview" })
assert(
    snapshot().status == "partial" and snapshot().stale,
    "Failed typed refresh marks its retained overview stale"
)
print(
    "Forges parity: daily calendars/timezones, public Tangled authored work and repository links, GitLab role unions and paginated read-only to-dos passed"
)
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
    snapshot().repository == "" and #snapshot().pulls == 0,
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
    "GitHub loads its pinned contribution calendar alongside the default queue"
)
respond(calendarFixture())
respondGh({ { full_name = "octocat/example", description = "Example" } })
assert(
    snapshot().status == "ready"
        and snapshot().view == "repositories"
        and snapshot().contributions.activity.months[6].values.commits > 0
        and #queue == 0
)
send({ op = "view", view = "repositories" })
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
assert(queue[1].argv[3] == "graphql", "Refresh reloads the visible pinned calendar too")
respond(calendarFixture())
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
local oldGraph = assert(table.remove(queue, 1))
assert(oldGraph.argv[3] == "graphql")
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
respondGh({})
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
respond(calendarFixture("other-account"))
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
-- Profile controls resolve only the target identity, even before its forge is selected.
boot()
service()
send({ op = "profile", provider = "tangled" })
assert(#queue == 1, "Profile clicks coalesce with initial account verification")
respond({ authenticated = true, handle = "alice.test" })
assert(lastLaunch[2] == "https://tangled.org/alice.test" and queue[1].argv[2] == "repo")
respond(tgRepo)
send({ op = "profile", provider = "github" })
assert(#queue == 1 and queue[1].argv[3] == "user")
respond({ id = 1, login = "octocat" })
assert(
    lastLaunch[2] == "https://github.com/octocat"
        and #queue == 0
        and snapshot().provider == "tangled",
    "Opening inactive profiles must not switch provider or fetch any queues or graph"
)
send({ op = "profile", provider = "github" })
assert(#queue == 0 and lastLaunch[2] == "https://github.com/octocat")
missingCommands["xdg-open"] = true
send({ op = "profile", provider = "tangled" })
assert(snapshot().action_error:find("Missing xdg-open", 1, true))
missingCommands["xdg-open"] = nil
send({ op = "profile", provider = "tangled" })
assert(snapshot().action_error == nil)
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

-- Six calendar months, not a rolling day-count window; preserve year/leap boundaries.
local activityClock = clock
clock = systemTime({ year = 2024, month = 2, day = 29, hour = 12 })
local chartMonths = Activity.months()
assert(#chartMonths == 6 and chartMonths[1].date == "2023-09" and chartMonths[6].date == "2024-02")
local monthlyQuery = GitHub.contributions()[5]
assert(monthlyQuery:find('from: "2023-09-01T00:00:00Z"', 1, true))
assert(monthlyQuery:find('to: "2024-01-31T23:59:59Z"', 1, true))
local metricFixture = { data = { viewer = { login = "octocat" } } }
for i, month in ipairs(chartMonths) do
    metricFixture.data.viewer["activity" .. tostring(i)] = {
        startedAt = month.date .. "-01T00:00:00Z",
        totalCommitContributions = 700 - i * 100,
        totalPullRequestContributions = i * 10,
        totalIssueContributions = 5,
        totalRepositoryContributions = i % 3,
    }
end
local multiActivity = assert(Activity.github(metricFixture))
local chartLayout = Activity.layout(multiActivity)
assert(chartLayout.width == 548 and chartLayout.height == 210)
assert(chartLayout.columns[6].left + chartLayout.columns[6].width == chartLayout.width)
assert(chartLayout.points.pulls[1].y > chartLayout.points.pulls[6].y)
assert(chartLayout.points.commits[1].y < chartLayout.points.commits[6].y)
for i = 1, 6 do
    local ys = {}
    for _, metric in ipairs(Activity.metrics) do
        local point = chartLayout.points[metric][i]
        assert(point.x == chartLayout.columns[i].left + 8 and point.y >= 20 and point.y <= 164)
        table.insert(ys, point.y)
    end
    table.sort(ys)
    for j = 2, #ys do
        assert(ys[j] - ys[j - 1] >= 28)
    end
end
local badMetric = copy(metricFixture)
badMetric.data.viewer.activity3.totalCommitContributions = -1
assert(not Activity.github(badMetric))
badMetric = copy(metricFixture)
badMetric.data.viewer.activity1.startedAt = "2000-01-01T00:00:00Z"
assert(not Activity.github(badMetric), "Never relabel stale monthly responses")
clock = activityClock
local tgFull = copy(tgActivity)
tgFull.months[1].pulls = { {} }
tgFull.months[1].issues = {}
tgFull.months[1].repos = { {}, {} }
local fullActivity = assert(Tangled.normalizeContributions(tgFull, "alice.test")).activity
assert(fullActivity.months[6].values.commits == 4)
assert(fullActivity.months[6].values.pulls == 1 and fullActivity.months[6].values.repos == 2)
assert(fullActivity.months[6].values.issues == 0 and not fullActivity.months[6].lowerBounds.pulls)
tgFull.truncated = true
local partialActivity = assert(Tangled.normalizeContributions(tgFull, "alice.test")).activity
assert(
    partialActivity.months[6].values.commits == 4
        and not partialActivity.months[6].lowerBounds.commits
)
assert(partialActivity.months[6].lowerBounds.pulls and partialActivity.months[1].lowerBounds.issues)
tgFull.months[1].pulls = "invalid"
assert(not Tangled.normalizeContributions(tgFull, "alice.test"))
local aggregateActivity = Activity.fromCalendar(normalCalendar)
assert(aggregateActivity.aggregate and aggregateActivity.months[6].values.contributions == 4)
assert(aggregateActivity.months[6].values.commits == nil, "Aggregate contributions are not commits")
local unknownLayout = Activity.layout({ months = Activity.months() })
for _, metric in ipairs(Activity.metrics) do
    for _, point in ipairs(unknownLayout.points[metric]) do
        assert(point.value == nil)
    end
end
print(
    "Forges activity: six-month boundaries, monthly GitHub credit, Tangled list truncation, aggregate fallback and collision layout passed"
)

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
    setWantsSecondTicks = function(value)
        secondTicks = value
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
    capabilities = { contributions = true },
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
local actions = lastPanel.children[1].children[3].children
assert(
    actions[1].props.text == nil and actions[2].props.text == nil and actions[3].props.text == nil,
    "Profile controls must be icon-only"
)
assert(
    actions[1].props.key == "profile-tangled"
        and actions[2].props.key == "profile-github"
        and actions[3].props.key == "profile-gitlab"
        and actions[4].props.tooltip == "Refresh",
    "All profile controls must sit immediately left of reload"
)
assert(
    lastPanel.children[2].props.key == "provider-switch"
        and lastPanel.children[3].props.key == "contribution-calendar",
    "Tangled graph failures must keep their own profile fallback above the work queue"
)
actions[1].props.onClick()
assert(lastCommand.op == "profile" and lastCommand.provider == "tangled")
actions[2].props.onClick()
assert(lastCommand.op == "profile" and lastCommand.provider == "github")
assert(find("button", function(props)
    return props.text == "Open profile activity"
end)).props.onClick()
assert(lastCommand.op == "profile" and lastCommand.provider == "tangled")
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
    return props.key == "provider-tangled"
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
    return props.key == "provider-github"
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
-- All providers now use the same bounded six-month chart, not 378 native day cells.
local graphSnapshot = {
    provider = "github",
    account = "octocat",
    view = "repositories",
    status = "ready",
    contributions = graphData,
    versions = { contributions = 1 },
    errors = {},
    loading = {},
}
settings["shell.corner_radius_scale"] = 0
local beforeChartNodes = nodeCreations
noctalia.state.set("forges.snapshot", graphSnapshot)
local grid = assert(find("image", function(props)
    return props.key:find("activity-chart-", 1, true) == 1
end))
assert(
    not wantsFrames and nodeCreations - beforeChartNodes < 100,
    "Six-month SVG must not need progressive frame work"
)
assert(grid.props.width == 548 and grid.props.height == 210 and grid.props.fit == "contain")
assert(imageFiles[grid.props.path]:find("<svg ", 1, true))
assert(lastPanel.children[3].props.key == "activity-section", "Activity stays pinned above queues")
local oldGrid, oldWrites = grid, imageWrites
noctalia.state.set("forges.snapshot", graphSnapshot)
assert(find("image", function()
    return true
end) == oldGrid and imageWrites == oldWrites)
settings["color.primary"] = "#bbccdd"
assert(secondTicks)
update()
grid = assert(find("image", function()
    return true
end))
assert(grid ~= oldGrid and grid.props.key ~= oldGrid.props.key and imageWrites == oldWrites + 1)
assert(imageFiles[grid.props.path]:find("#bbccdd", 1, true), "Theme changes regenerate themed SVGs")
local paletteWrites = imageWrites
update()
assert(imageWrites == paletteWrites, "Second ticks must not rewrite unchanged charts")
onClose()
assert(not secondTicks)
onOpen()
assert(secondTicks)
assert(find("image", function()
    return true
end) == grid and not wantsFrames)
local pinnedGrid = grid
graphSnapshot.view = "issues"
noctalia.state.set("forges.snapshot", graphSnapshot)
assert(lastPanel.children[3].props.key == "activity-section")
assert(find("image", function()
    return true
end) == pinnedGrid)
assert(find("button", function(props)
    return props.key == "activity-month-1"
end)).props.onClick()
assert(find("label", function(props)
    return props.text:find(Activity.months()[1].date, 1, true) == 1
end))
local sparseGraph = copy(graphData)
sparseGraph.weeks[1].days[1] = false
sparseGraph.weeks[#sparseGraph.weeks].days[7] = false
sparseGraph.activity = Activity.fromCalendar(sparseGraph)
sparseGraph.activity.months[6].values.contributions = 99
graphSnapshot.contributions, graphSnapshot.versions.contributions = sparseGraph, 2
noctalia.state.set("forges.snapshot", graphSnapshot)
assert(find("image", function()
    return true
end) ~= pinnedGrid)
local lastGoodImage = find("image", function()
    return true
end)
failImageWrite = true
sparseGraph.activity.months[6].values.contributions = 100
graphSnapshot.versions.contributions = 3
noctalia.state.set("forges.snapshot", graphSnapshot)
assert(find("image", function()
    return true
end) == lastGoodImage, "Write failures retain same-account last-good image")
assert(find("label", function(props)
    return props.text:find("Could not write activity chart", 1, true) == 1
end))
failImageWrite = false
noctalia.state.set("forges.snapshot", graphSnapshot)
assert(find("image", function()
    return true
end) ~= lastGoodImage)
local sameImage, sameWrites = find("image", function()
    return true
end), imageWrites
graphSnapshot.versions.contributions = 4
noctalia.state.set("forges.snapshot", graphSnapshot)
assert(
    find("image", function()
        return true
    end) == sameImage and imageWrites == sameWrites,
    "Identical refreshed SVGs reuse their image and file"
)
local imageFileCount = 0
for _ in pairs(imageFiles) do
    imageFileCount += 1
end
assert(imageFileCount == 1, "Refreshes must not accumulate SVG files or leave temporary files")
local tgCalendar = copy(graphData)
tgCalendar.unit, tgCalendar.caption = "commits", "4 public commits in 2023"
noctalia.state.set("forges.snapshot", {
    provider = "tangled",
    account = "alice.test",
    view = "issues",
    status = "ready",
    repository = "owner/project",
    capabilities = { contributions = false },
    contributions = tgCalendar, -- A previous plugin version may have left a scraped graph in shared state.
    versions = { contributions = 2 },
    errors = {},
})
assert(not wantsFrames, "External activity must not prepare or retain a contribution grid")
for _ = 1, 14 do
    onFrameTick()
end
assert(not find("label", function(props)
    return props.text == "4 public commits in 2023"
end))
assert(not find("row", function(props)
    return props.key == "contribution-grid"
end))
assert(find("row", function(props)
    return props.key == "external-activity"
end))
assert(find("button", function(props)
    return props.text == "Open profile activity"
end)).props.onClick()
assert(lastCommand.op == "profile" and lastCommand.provider == "tangled")
onClose()
onOpen()
assert(not wantsFrames and find("row", function(props)
    return props.key == "external-activity"
end))
assert(find("button", function(props)
    return props.text == "Authored work"
end)).props.onClick()
assert(lastCommand.repository == "")
local monthlySnapshot = {
    provider = "tangled",
    account = "alice.test",
    status = "ready",
    view = "issues",
    capabilities = { contributions = true },
    contributions = tgMonthly,
    versions = { contributions = 3 },
    errors = {},
}
noctalia.state.set("forges.snapshot", monthlySnapshot)
local monthlyNode = assert(find("image", function()
    return true
end))
assert(not wantsFrames and lastPanel.children[3].props.key == "activity-section")
assert(not find("label", function(props)
    return props.text:find("Current streak", 1, true) ~= nil
end))
assert(find("button", function(props)
    return props.key == "activity-month-6"
end)).props.onClick()
assert(find("label", function(props)
    return props.text:find(today:sub(1, 7), 1, true) == 1 and props.text:find("4 commits", 1, true)
end))
monthlySnapshot.loading = { contributions = true }
monthlySnapshot.errors.contributions = "Temporary network failure"
noctalia.state.set("forges.snapshot", monthlySnapshot)
assert(find("image", function()
    return true
end) == monthlyNode)
assert(find("label", function(props)
    return props.text == "Temporary network failure"
end))
monthlySnapshot.errors, monthlySnapshot.loading = {}, {}
noctalia.state.set("forges.snapshot", monthlySnapshot)
onClose()
onOpen()
assert(not wantsFrames and find("image", function()
    return true
end) == monthlyNode)
local retainedTangledSnapshot = copy(values["forges.snapshot"])
local glPanel = {
    provider = "gitlab",
    account = "student",
    base_url = "https://gitlab.com",
    view = "notifications",
    status = "ready",
    contributions = normalCalendar,
    versions = { contributions = 2 },
    notifications = todoData.rows,
    notification_has_more = true,
    errors = {},
}
noctalia.state.set("forges.snapshot", glPanel)
assert(not wantsFrames)
assert(find("label", function(props)
    return props.text == "Review assignment"
end))
assert(find("label", function(props)
    return props.text == "Submitted"
end))
local commandBeforeFilters = lastCommand
assert(find("button", function(props)
    return props.text == "Pending"
end)).props.onClick()
assert(find("label", function(props)
    return props.text == "Review assignment"
end))
assert(not find("label", function(props)
    return props.text == "Submitted"
end))
assert(find("button", function(props)
    return props.text == "Done"
end)).props.onClick()
assert(find("label", function(props)
    return props.text == "Submitted"
end))
assert(not find("label", function(props)
    return props.text == "Review assignment"
end))
assert(lastCommand == commandBeforeFilters, "To-do filters must remain local and read-only")
assert(find("button", function(props)
    return props.text == "Load older to-dos"
end)).props.onClick()
assert(lastCommand.op == "notifications_more")
local retainedGitLabGrid = assert(find("image", function()
    return true
end))
local retainedSnapshot = copy(values["forges.snapshot"])
noctalia.state.set("forges.snapshot", graphSnapshot)
local retainedGitHubGrid = assert(find("image", function()
    return true
end))
noctalia.state.set("forges.snapshot", retainedSnapshot)
assert(not wantsFrames and find("image", function()
    return true
end) == retainedGitLabGrid)
onClose()
onOpen()
assert(not wantsFrames and find("image", function()
    return true
end) == retainedGitLabGrid)
noctalia.state.set("forges.snapshot", graphSnapshot)
assert(find("image", function()
    return true
end) == retainedGitHubGrid)
noctalia.state.set("forges.snapshot", retainedTangledSnapshot)
assert(find("image", function()
    return true
end) == monthlyNode, "Each forge retains its own prepared chart")
noctalia.state.set("forges.snapshot", graphSnapshot)
local anotherAccount = copy(graphSnapshot)
anotherAccount.account = "another-account"
failImageWrite = true
noctalia.state.set("forges.snapshot", anotherAccount)
assert(not find("image", function()
    return true
end), "Never retain another account's SVG after write failure")
assert(imageFiles[retainedGitHubGrid.props.path] == nil, "Clear the old account's cached file")
failImageWrite = false
noctalia.state.set("forges.snapshot", anotherAccount)
assert(find("image", function()
    return true
end) ~= retainedGitHubGrid)
local closedAccountImage = find("image", function()
    return true
end)
onClose()
local closedRenders = panelRenders
anotherAccount.contributions = nil
noctalia.state.set("forges.snapshot", anotherAccount)
assert(
    imageFiles[closedAccountImage.props.path] == nil and panelRenders == closedRenders,
    "Closed panels clear invalidated private SVGs without rebuilding the UI"
)
onOpen()

noctalia.state.set("forges.snapshot", {
    provider = "gitlab",
    base_url = "https://gitlab.school.edu",
    account = "student",
    status = "ready",
    view = "repositories",
    repository = "school/course/project",
    repositories = GitLab.normalizeRepositories(glRepos),
    pulls = {},
    issues = {},
    errors = {},
})
assert(find("button", function(props)
    return props.text == "GitLab"
end))
assert(find("button", function(props)
    return props.text == "Merge requests"
end))
assert(find("button", function(props)
    return props.text == "To-dos"
end))
assert(lastPanel.children[3].props.key == "contribution-calendar")
assert(find("button", function(props)
    return props.text == "Open profile activity"
end)).props.onClick()
assert(lastCommand.provider == "gitlab")
local repoInput = assert(find("input", function(props)
    return props.key == "repository-gitlab"
end))
repoInput.props.onChange("school/course/project")
onInspectRepository()
assert(lastCommand.repository == "school/course/project")

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
noctalia.state.set(
    "forges.snapshot",
    { provider = "gitlab", account = "student", status = "ready" }
)
assert(tooltip:find("GitLab", 1, true))
print(
    "Forges: GitLab custom hosts, nested groups, merge requests/issues, instance/account invalidation, shared monthly SVG header, theme/file failure recovery, independent profile actions, provider/resource caches, inbox history/filters, account invalidation, race/error recovery and native surfaces passed"
)
