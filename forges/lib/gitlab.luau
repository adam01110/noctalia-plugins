local Activity = require("./activity.luau")
local GitLab = {}
function GitLab.instance(value)
    if value == nil or value == "" then
        value = "https://gitlab.com"
    end
    if type(value) ~= "string" then
        return nil
    end
    local host = value:match("^https://([%w%.%-:]+)/?$")
    if not host then
        return nil
    end
    local hostname, port = host:match("^([^:]+):(%d+)$")
    hostname = hostname or host
    if hostname:find(":", 1, true) or hostname:find("..", 1, true) then
        return nil
    end
    for label in hostname:gmatch("[^%.]+") do
        if not label:match("^[%w]") or not label:match("[%w]$") then
            return nil
        end
    end
    if not hostname:match("^[%w]") or not hostname:match("[%w]$") then
        return nil
    end
    if port and (tonumber(port) < 1 or tonumber(port) > 65535) then
        return nil
    end
    return "https://" .. host:lower(), host:lower()
end
function GitLab.validRepository(value)
    if type(value) ~= "string" or #value > 500 or not value:find("/", 1, true) then
        return false
    end
    if value:sub(1, 1) == "/" or value:sub(-1) == "/" or value:find("//", 1, true) then
        return false
    end
    for part in value:gmatch("[^/]+") do
        if not part:match("^[%w_%.%-]+$") or part == "." or part == ".." then
            return false
        end
    end
    return true
end
local function api(host, endpoint)
    return { "glab", "api", endpoint, "--hostname", host }
end
function GitLab.profile(host)
    return api(host, "user")
end
function GitLab.repositories(host)
    return api(host, "projects?membership=true&order_by=last_activity_at&per_page=50")
end
function GitLab.work(host, kind, repository, login)
    if repository == "" then
        local fields = "nodes { iid title state updatedAt webUrl "
            .. (kind == "pulls" and "project { fullPath } " or "")
            .. "author { username } }"
        local query
        if kind == "pulls" then
            query = "query { currentUser { username "
                .. "authored: authoredMergeRequests(state: opened, sort: UPDATED_DESC, first: 30) { "
                .. fields
                .. " } "
                .. "assigned: assignedMergeRequests(state: opened, sort: UPDATED_DESC, first: 30) { "
                .. fields
                .. " } "
                .. "reviewing: reviewRequestedMergeRequests(state: opened, sort: UPDATED_DESC, first: 30) { "
                .. fields
                .. " } } }"
        else
            query = "query($login: String!) { currentUser { username } "
                .. "authored: issues(authorUsername: $login, state: opened, sort: UPDATED_DESC, first: 30) { "
                .. fields
                .. " } "
                .. "assigned: issues(assigneeUsernames: [$login], state: opened, sort: UPDATED_DESC, first: 30) { "
                .. fields
                .. " } }"
        end
        local argv = { "glab", "api", "graphql", "--hostname", host, "-f", "query=" .. query }
        if kind ~= "pulls" then
            table.insert(argv, "-f")
            table.insert(argv, "login=" .. login)
        end
        return argv
    end
    local project = repository:gsub("[^%w%-_%.~]", function(char)
        return string.format("%%%02X", string.byte(char))
    end)
    return api(
        host,
        "projects/"
            .. project
            .. "/"
            .. (kind == "pulls" and "merge_requests" or "issues")
            .. "?scope=all&state=opened&order_by=updated_at&per_page=30"
    )
end
function GitLab.normalizeProfile(raw)
    if type(raw.username) ~= "string" or raw.username == "" or raw.id == nil then
        return nil
    end
    return { id = tostring(raw.id), login = raw.username, name = raw.name or raw.username }
end
function GitLab.normalizeRepositories(raw)
    if raw.message ~= nil or raw.error ~= nil then
        return nil
    end
    local out = {}
    for i, item in ipairs(raw) do
        if i > 50 then
            break
        end
        if type(item.path_with_namespace) == "string" then
            table.insert(out, {
                name = item.path_with_namespace,
                description = item.description or "",
                url = item.web_url or "",
                updatedAt = item.last_activity_at or "",
            })
        end
    end
    return out
end
function GitLab.normalizeWork(raw, repository, login)
    if repository == "" then
        if raw.errors and next(raw.errors) then
            return nil
        end
        local user = raw.data and raw.data.currentUser
        if not user or user.username ~= login then
            return nil
        end
        local source = user.authored and user or raw.data
        local out, seen = {}, {}
        for _, role in
            ipairs(
                source == user and { "authored", "assigned", "reviewing" }
                    or { "authored", "assigned" }
            )
        do
            local connection = source[role]
            if
                type(connection) ~= "table"
                or type(connection.nodes) ~= "table"
                or #connection.nodes > 30
            then
                return nil
            end
            for _, item in ipairs(connection.nodes) do
                if type(item.webUrl) ~= "string" then
                    return nil
                end
                local name = item.project and item.project.fullPath
                    or item.webUrl:match("^https://[^/]+/(.+)/%-/issues/%d+$")
                if not GitLab.validRepository(name) then
                    return nil
                end
                if not seen[item.webUrl] then
                    seen[item.webUrl] = true
                    table.insert(out, {
                        id = tostring(item.iid or ""),
                        title = item.title or "",
                        repository = name,
                        author = item.author and item.author.username or "",
                        state = item.state or "opened",
                        updatedAt = item.updatedAt or "",
                        url = item.webUrl,
                    })
                end
            end
        end
        table.sort(out, function(a, b)
            return a.updatedAt > b.updatedAt or (a.updatedAt == b.updatedAt and a.url < b.url)
        end)
        while #out > 30 do
            table.remove(out)
        end
        return out
    end
    if raw.message ~= nil or raw.error ~= nil then
        return nil
    end
    local out = {}
    for i, item in ipairs(raw) do
        if i > 30 then
            break
        end
        table.insert(out, {
            id = tostring(item.iid or ""),
            title = item.title or "",
            repository = repository,
            author = type(item.author) == "table" and item.author.username or "",
            state = item.state or "opened",
            updatedAt = item.updated_at or "",
            url = item.web_url or "",
        })
    end
    return out
end
function GitLab.contributions(host)
    return {
        "glab",
        "api",
        "graphql",
        "--hostname",
        host,
        "-f",
        "query=query { currentUser { username contributionCalendar { totalCount utcOffset days { date count } } } }",
    }
end
function GitLab.normalizeContributions(raw)
    if raw.errors and next(raw.errors) then
        return nil
    end
    local user = raw.data and raw.data.currentUser
    local calendar = user and user.contributionCalendar
    if type(calendar) ~= "table" or type(calendar.days) ~= "table" then
        return nil
    end
    local counts = {}
    for _, day in ipairs(calendar.days) do
        if
            type(day.date) ~= "string"
            or not day.date:match("^%d%d%d%d%-%d%d%-%d%d$")
            or type(day.count) ~= "number"
            or counts[day.date] ~= nil
        then
            return nil
        end
        counts[day.date] = day.count
    end
    return {
        login = user.username,
        counts = counts,
        utcOffset = calendar.utcOffset,
        total = calendar.totalCount,
    }
end
function GitLab.notifications(host, cursor)
    local argv = {
        "glab",
        "api",
        "graphql",
        "--hostname",
        host,
        "-f",
        "query=query($cursor: String) { currentUser { username todos(state: [pending, done], first: 50, after: $cursor) { nodes { id body state createdAt targetUrl author { username } project { fullPath } } pageInfo { hasNextPage endCursor } } } }",
    }
    if cursor then
        table.insert(argv, "-f")
        table.insert(argv, "cursor=" .. cursor)
    end
    return argv
end
function GitLab.normalizeNotifications(raw, login)
    if raw.errors and next(raw.errors) then
        return nil
    end
    local user = raw.data and raw.data.currentUser
    local todos = user and user.todos
    if
        not user
        or user.username ~= login
        or type(todos) ~= "table"
        or type(todos.nodes) ~= "table"
        or type(todos.pageInfo) ~= "table"
    then
        return nil
    end
    local out = {}
    for i, todo in ipairs(todos.nodes) do
        if
            i > 50
            or type(todo.id) ~= "string"
            or (todo.state ~= "pending" and todo.state ~= "done")
        then
            return nil
        end
        table.insert(out, {
            id = todo.id,
            title = todo.body or "",
            repository = todo.project and todo.project.fullPath or "",
            author = todo.author and todo.author.username or "",
            state = todo.state,
            updatedAt = todo.createdAt or "",
            url = todo.targetUrl or "",
        })
    end
    local more, cursor = todos.pageInfo.hasNextPage == true, todos.pageInfo.endCursor
    if more and (type(cursor) ~= "string" or cursor == "" or #cursor > 4096) then
        return nil
    end
    return { rows = out, has_more = more, cursor = cursor }
end
function GitLab.activity(host, login)
    local months, pulls, issues = Activity.months(), {}, {}
    for i, month in ipairs(months) do
        local untilDate = Activity.monthEnd(months, i)
        local range = '(createdAfter: "'
            .. month.date
            .. '-01T00:00:00Z", createdBefore: "'
            .. untilDate
            .. '", includeArchived: true) { count(limit: 10000) }'
        table.insert(pulls, "pulls" .. tostring(i) .. ": authoredMergeRequests" .. range)
        table.insert(
            issues,
            "issues"
                .. tostring(i)
                .. ": issues"
                .. range:gsub("%(createdAfter:", "(authorUsername: $login, createdAfter:", 1)
        )
    end
    local query = "query ForgesActivity($login: String!) { currentUser { username "
        .. table.concat(pulls, " ")
        .. " } "
        .. table.concat(issues, " ")
        .. " }"
    return {
        "glab",
        "api",
        "graphql",
        "--hostname",
        host,
        "-f",
        "query=" .. query,
        "-f",
        "login=" .. login,
    }
end
function GitLab.normalizeActivity(raw, login)
    if raw.errors and next(raw.errors) then
        return nil
    end
    local user = raw.data and raw.data.currentUser
    if not user or user.username ~= login then
        return nil
    end
    local months = Activity.months()
    for i, month in ipairs(months) do
        for _, metric in ipairs({ "pulls", "issues" }) do
            local source = metric == "pulls" and user or raw.data
            local connection = source[metric .. tostring(i)]
            if
                type(connection) ~= "table"
                or not Activity.count(connection.count)
                or connection.count > 10001
            then
                return nil
            end
            month.values[metric] = connection.count
            month.lowerBounds[metric] = connection.count == 10001
        end
    end
    return {
        months = months,
        note = "Authored MRs/issues · commits and new repositories unavailable · independent scales",
    }
end
return GitLab
