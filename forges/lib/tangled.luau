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
return Tangled
