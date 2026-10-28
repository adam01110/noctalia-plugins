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
function Tangled.contributions(account)
    return publicGet("https://tangled.org/" .. account)
end
function Tangled.newContributions(raw, login)
    if type(raw.html) ~= "string" or #raw.html > 1048576 then
        return nil, "profile HTML is absent or exceeds the response limit"
    end
    return { html = raw.html, login = login, cursor = 1, counts = {}, count = 0, phase = "tags" }
end
function Tangled.stepContributions(job)
    if job.done then
        return true
    end
    local function fail(error)
        job.done, job.error, job.html = true, error, nil
        return true
    end
    for _ = 1, 16 do
        if job.phase == "tags" then
            local start = job.html:find(job.depth and "<" or "<div", job.cursor, true)
            if not start then
                return fail(
                    job.depth and "profile HTML ended before the punchcard grid closed"
                        or "Tangled returned no public commit punchcard. Open profile activity to check availability."
                )
            end
            local finish = job.html:find(">", start + 1, true)
            if not finish then
                return fail("profile contains an incomplete HTML tag")
            end
            if finish - start > 8192 then
                if job.depth then
                    return fail("punchcard contains an oversized HTML tag")
                end
                job.cursor = finish + 1
                continue
            end
            local tag = job.html:sub(start, finish)
            job.cursor = finish + 1
            local opening = tag:match("^<div[%s>]") ~= nil
            local closing = tag:match("^</div%s*>") ~= nil
            if not job.depth then
                if opening and tag:match("%sdata%-punchcard[%s=>]") then
                    job.depth = 1
                end
            else
                if opening then
                    job.depth += 1
                end
                if closing then
                    job.depth -= 1
                end
                local date, count = tag:match('title="(%d%d%d%d%-%d%d%-%d%d): (%d+) commits?"')
                if date then
                    if job.counts[date] ~= nil or (job.year and job.year ~= date:sub(1, 4)) then
                        return fail("punchcard contains duplicate dates or multiple years")
                    end
                    local n = tonumber(count)
                    if not n or n > 1000000000 then
                        return fail("punchcard contains an invalid commit count")
                    end
                    job.counts[date], job.year, job.count = n, date:sub(1, 4), job.count + 1
                    if job.count > 366 then
                        return fail("punchcard has too many dates")
                    end
                end
                if job.depth == 0 then
                    local today = os.date("!%Y-%m-%d", os.time())
                    if (job.count ~= 365 and job.count ~= 366) or job.year ~= today:sub(1, 4) then
                        return fail(
                            "Tangled returned an incomplete or unsupported public commit calendar."
                        )
                    end
                    job.stamp = os.time({ year = tonumber(job.year), month = 1, day = 1, hour = 0 })
                    job.last = os.time({
                        year = tonumber(job.year) + 1,
                        month = 1,
                        day = 1,
                        hour = 0,
                    }) - 86400
                    job.expected, job.phase, job.html = 0, "dates", nil
                    break
                end
            end
        else
            if job.stamp > job.last then
                if job.count ~= job.expected then
                    return fail("punchcard day count disagrees with its declared year")
                end
                job.value = {
                    counts = job.counts,
                    login = job.login,
                    firstDate = job.year .. "-01-01",
                    year = job.year,
                }
                job.done = true
                return true
            end
            if job.counts[os.date("!%Y-%m-%d", job.stamp)] == nil then
                return fail("punchcard is missing a day in its declared year")
            end
            job.expected += 1
            job.stamp += 86400
        end
    end
    return false
end
function Tangled.normalizeContributions(raw, login)
    local job, error = Tangled.newContributions(raw, login)
    if not job then
        return nil, error
    end
    while not Tangled.stepContributions(job) do
    end
    return job.value, job.error
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
