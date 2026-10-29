-- tg's JSON envelopes are intentionally normalized at the provider boundary.
local Tangled = {}
function Tangled.profile()
    return { "tg", "auth", "status", "--json" }
end
function Tangled.repositories(account)
    local argv = { "tg", "repo", "list", "--json" }
    if account then
        table.insert(argv, "--account")
        table.insert(argv, account)
    end
    return argv
end
function Tangled.work(kind, repository, account)
    local argv = {
        "tg",
        kind == "pulls" and "pr" or "issue",
        "list",
        repository,
        "--state",
        "open",
        "--limit",
        "30",
        "--json",
    }
    if account then
        table.insert(argv, "--account")
        table.insert(argv, account)
    end
    return argv
end
function Tangled.normalizeProfile(raw)
    if raw.authenticated ~= true or type(raw.handle) ~= "string" or raw.handle == "" then
        return nil
    end
    return { id = raw.did or raw.handle, login = raw.handle, name = raw.handle }
end
function Tangled.normalizeRepositories(raw)
    if type(raw.items) ~= "table" then
        return nil
    end
    local out = {}
    for i, item in ipairs(raw.items) do
        if i > 50 then
            break
        end
        if type(item.author) == "string" and type(item.name) == "string" then
            local name = item.author .. "/" .. item.name
            table.insert(out, {
                name = name,
                description = item.description or "",
                url = "https://tangled.org/" .. name,
                updatedAt = item.createdAt or "",
            })
        end
    end
    return out
end
function Tangled.normalizeWork(raw, repository, kind)
    if type(raw.items) ~= "table" then
        return nil
    end
    local out = {}
    for i, item in ipairs(raw.items) do
        if i > 30 then
            break
        end
        local id = tostring(item.rkey or "")
        table.insert(out, {
            id = id,
            title = item.title or "",
            repository = repository,
            author = type(item.author) == "table" and (item.author.handle or item.author.did) or "",
            state = item.state or "open",
            updatedAt = item.updatedAt or item.createdAt or "",
            -- tg 0.6 returns record keys, not the AppView's numeric web IDs.
            -- A record key is not a valid /issues/<number> or /pulls/<number> URL.
            url = "https://tangled.org/"
                .. repository
                .. "/"
                .. (kind == "pulls" and "pulls" or "issues"),
            linkLabel = kind == "pulls" and "Open repository pull requests"
                or "Open repository issues",
        })
    end
    return out
end
local function publicGet(url)
    return {
        "curl",
        "--fail",
        "--silent",
        "--show-error",
        "--location",
        "--max-redirs",
        "3",
        "--proto-redir",
        "=https",
        "--max-time",
        "20",
        "--max-filesize",
        "1048576",
        "--proto",
        "=https",
        "--",
        url,
    }
end
local function encode(value)
    return value:gsub("[^%w%-_%.~]", function(char)
        return string.format("%%%02X", string.byte(char))
    end)
end
function Tangled.authoredWork(kind, account)
    return publicGet(
        "https://api.tangled.org/xrpc/sh.tangled.repo."
            .. (kind == "pulls" and "listPullsBy" or "listIssuesBy")
            .. "?subject="
            .. encode(account)
            .. "&limit=100&order=desc"
    )
end
function Tangled.repositoryInfo(repoDid)
    return publicGet(
        "https://api.tangled.org/xrpc/sh.tangled.repo.getRepoByRepoDid?repoDid=" .. encode(repoDid)
    )
end
function Tangled.normalizeRepositoryInfo(raw)
    if type(raw.uri) ~= "string" then
        return nil
    end
    local owner, name = raw.uri:match("^at://([^/]+)/sh%.tangled%.repo/([^/]+)$")
    if
        not owner
        or not name
        or not owner:match("^did:[%w:%.%-]+$")
        or not name:match("^[%w_%.%-]+$")
        or name == "."
        or name == ".."
    then
        return nil
    end
    return { name = owner .. "/" .. name, url = "https://tangled.org/" .. owner .. "/" .. name }
end
function Tangled.normalizeAuthoredWork(raw, account, login, kind)
    if type(raw.items) ~= "table" or #raw.items > 100 then
        return nil
    end
    local out = {}
    for _, item in ipairs(raw.items) do
        if type(item.uri) ~= "string" then
            return nil
        end
        local author, collection, key = item.uri:match("^at://([^/]+)/([^/]+)/([^/]+)$")
        local value = item.value
        if
            author ~= account
            or collection ~= (kind == "pulls" and "sh.tangled.repo.pull" or "sh.tangled.repo.issue")
            or type(value) ~= "table"
        then
            return nil
        end
        local repo = value.repo
        if kind == "pulls" then
            repo = type(value.target) == "table" and value.target.repo or nil
        end
        if
            type(repo) ~= "string"
            or not repo:match("^did:[%w:%.%-]+$")
            or (
                item.state ~= "open"
                and item.state ~= "closed"
                and not (kind == "pulls" and item.state == "merged")
            )
        then
            return nil
        end
        -- Bobbin's author views can ignore state filters; inspect the newest 100 records locally.
        if item.state == "open" and #out < 30 then
            table.insert(out, {
                id = key,
                uri = item.uri,
                title = value.title or "",
                repository = repo,
                repoDid = repo,
                author = login,
                state = item.state,
                updatedAt = item.stateUpdatedAt or value.createdAt or "",
                url = "https://tangled.org/" .. login,
                linkLabel = "Open author profile (repository unavailable)",
            })
        end
    end
    return out
end
return Tangled
