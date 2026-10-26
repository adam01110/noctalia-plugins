-- Adapted from Shangshui0302's GitHub Kanban (MIT).
-- Read-only argv requests; no shell interpolation or notification mutations.
local GitHub = {}
function GitHub.profile()
    return { "gh", "api", "user", "--jq", "{id, login, name}", "--hostname", "github.com" }
end
function GitHub.repositories()
    return {
        "gh",
        "api",
        "user/repos?sort=updated&per_page=50",
        "--jq",
        "[.[] | {full_name, description, html_url, updated_at}]",
        "--hostname",
        "github.com",
    }
end
function GitHub.work(kind, repository)
    local query = repository ~= "" and ("repo:" .. repository) or "involves:@me"
    query ..= "+is:open+is:" .. (kind == "pulls" and "pr" or "issue")
    return {
        "gh",
        "api",
        "search/issues?q=" .. query .. "&sort=updated&per_page=30",
        "--jq",
        "{items: [.items[] | {number, title, repository_url, user: {login: .user.login}, state, html_url, updated_at}]}",
        "--hostname",
        "github.com",
    }
end
function GitHub.notifications(page)
    return {
        "gh",
        "api",
        "notifications?all=true&per_page=50&page=" .. tostring(page or 1),
        "--jq",
        "[.[] | {id, subject, repository: {full_name: .repository.full_name}, reason, unread, updated_at}]",
        "--hostname",
        "github.com",
    }
end
function GitHub.contributions()
    local query =
        [[query { viewer { login contributionsCollection { contributionCalendar { totalContributions weeks { contributionDays { date weekday contributionCount contributionLevel } } } } } }]]
    return { "gh", "api", "graphql", "-f", "query=" .. query, "--hostname", "github.com" }
end
return GitHub
