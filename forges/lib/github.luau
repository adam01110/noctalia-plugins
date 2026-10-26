-- Adapted from Shangshui0302's GitHub Kanban (MIT).
-- Read-only argv requests; no shell interpolation or notification mutations.
local GitHub = {}
function GitHub.profile()
    return { "gh", "api", "user", "--jq", "{login, name}" }
end
function GitHub.repositories()
    return {
        "gh",
        "api",
        "user/repos?sort=updated&per_page=50",
        "--jq",
        "[.[] | {full_name, description, html_url, updated_at}]",
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
    }
end
function GitHub.notifications()
    return {
        "gh",
        "api",
        "notifications?per_page=30",
        "--jq",
        "[.[] | {id, subject, repository: {full_name: .repository.full_name}, reason, unread, updated_at}]",
    }
end
return GitHub
