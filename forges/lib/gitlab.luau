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
function GitLab.work(host, kind, repository)
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
function GitLab.normalizeWork(raw, repository)
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
return GitLab
