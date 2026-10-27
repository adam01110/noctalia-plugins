--!nonstrict
local GitLab = require("./lib/gitlab.luau")
local GitHub = require("./lib/github.luau")
local Data = require("./lib/data.luau")
local Tangled = require("./lib/tangled.luau")

local function defaultProvider()
    local value = noctalia.getConfig("provider")
    return (value == "github" or value == "gitlab") and value or "tangled"
end
local provider = defaultProvider()
local configuredProvider = provider
local contexts = {}
local gitlabUrl, gitlabHost = GitLab.instance(noctalia.getConfig("gitlab_url"))
local sequence = 0
local actionError
local ensureView
local function interval()
    local minutes = tonumber(noctalia.getConfig("refresh_interval_minutes")) or 15
    if minutes ~= minutes or math.abs(minutes) == math.huge then
        minutes = 15
    end
    return math.clamp(minutes, 5, 60) * 60
end
local function resource()
    return { loading = false }
end
local function context(forge)
    if not contexts[forge] then
        contexts[forge] = {
            provider = forge,
            account = "",
            accountId = "",
            epoch = 0,
            repository = "",
            view = "repositories",
            profile = resource(),
            repositories = resource(),
            contributions = resource(),
            notifications = resource(),
            work = {},
        }
    end
    return contexts[forge]
end
local function work(ctx)
    local scope = ctx.repository
    if not ctx.work[scope] then
        -- Bound visited repository scopes, without evicting an in-flight request.
        local count, oldest, age = 0, nil, math.huge
        for key, entry in pairs(ctx.work) do
            count += 1
            if not entry.pulls.loading and not entry.issues.loading and entry.used < age then
                oldest, age = key, entry.used
            end
        end
        if count >= 8 then
            if oldest == nil then
                ctx.scopeError =
                    "Repository request limit reached. Retry when current requests finish."
                return nil
            end
            ctx.work[oldest] = nil
        end
        ctx.work[scope] = { pulls = resource(), issues = resource() }
    end
    ctx.scopeError = nil
    sequence += 1
    ctx.work[scope].used = sequence
    return ctx.work[scope]
end
local function selectedResource(ctx)
    if ctx.view == "pulls" or ctx.view == "issues" then
        local entry = ctx.work[ctx.repository]
        return entry and entry[ctx.view] or nil
    end
    return ctx[ctx.view == "overview" and "contributions" or ctx.view]
end
local function publish(ctx)
    if ctx.provider ~= provider then
        return
    end
    local entry = ctx.work[ctx.repository] or {}
    local selected = selectedResource(ctx)
    local errors, loading, versions = {}, {}, {}
    local resources = {
        account = ctx.profile,
        repositories = ctx.repositories,
        contributions = ctx.contributions,
        notifications = ctx.notifications,
        pulls = entry.pulls,
        issues = entry.issues,
    }
    for key, item in pairs(resources) do
        if item.error then
            errors[key] = item.error
        end
        loading[key] = item.loading
        versions[key] = item.version or 0
    end
    if (ctx.view == "pulls" or ctx.view == "issues") and ctx.scopeError then
        errors[ctx.view] = ctx.scopeError
    end
    local failed = ctx.profile.error
        or (selected and selected.error)
        or ((ctx.view == "pulls" or ctx.view == "issues") and ctx.scopeError or nil)
    local busy = ctx.profile.loading or (selected and selected.loading) or false
    local status = ctx.authError and "auth_error"
        or (
            ctx.missingCli and "missing_cli"
            or (busy and "loading" or (failed and "partial" or "ready"))
        )
    noctalia.state.set("forges.snapshot", {
        provider = ctx.provider,
        base_url = ctx.provider == "gitlab" and gitlabUrl or nil,
        account = ctx.account,
        repository = ctx.repository,
        view = ctx.view,
        status = status,
        stale = failed ~= nil and selected ~= nil and selected.value ~= nil,
        updated_at = selected and selected.updated_at or nil,
        repositories = ctx.repositories.value or {},
        contributions = ctx.contributions.value,
        notifications = ctx.notifications.value or {},
        pulls = entry.pulls and entry.pulls.value or {},
        issues = entry.issues and entry.issues.value or {},
        errors = errors,
        loading = loading,
        versions = versions,
        notification_has_more = ctx.notifications.has_more == true,
        notification_page = ctx.notifications.page or 0,
        action_error = actionError,
    })
end
local function invalidate(ctx)
    ctx.epoch += 1
    ctx.account, ctx.accountId, ctx.repository = "", "", ""
    ctx.repositories, ctx.contributions, ctx.notifications = resource(), resource(), resource()
    ctx.work, ctx.scopeError = {}, nil
end
local function fresh(item)
    -- A failed request is throttled independently, and does not erase its last success.
    return item.attempted_at ~= nil and os.time() - item.attempted_at < interval()
end
local function decodeResult(ctx, result)
    if result.exitCode ~= 0 then
        local stderr = string.lower(result.stderr or "")
        local auth = stderr:find("401", 1, true)
            or stderr:find("not logged", 1, true)
            or stderr:find("authentication", 1, true)
            or stderr:find("login required", 1, true)
            or stderr:find("gh auth login", 1, true)
            or stderr:find("tg auth login", 1, true)
            or stderr:find("glab auth login", 1, true)
        local cli = ctx.provider == "github" and "gh"
            or (ctx.provider == "gitlab" and "glab" or "tg")
        local login = cli == "tg" and "tg auth login <handle>"
            or (
                cli == "glab" and ("glab auth login --hostname " .. (gitlabHost or "<host>"))
                or "gh auth login"
            )
        return nil,
            auth and ("Sign in with " .. login .. ".")
                or ("Request failed. Check network access and " .. cli .. " authentication."),
            auth ~= nil
    end
    local ok, raw = pcall(noctalia.json.decode, result.stdout or "")
    if not ok or type(raw) ~= "table" then
        return nil, "Invalid JSON returned by forge CLI."
    end
    if raw.authenticated == false then
        return nil, "Sign in with tg auth login <handle>.", true
    end
    return raw
end
local function request(ctx, item, argv, normalize, force, after, failed)
    if item.loading then
        return
    end
    if not force and fresh(item) then
        if item.value ~= nil and after then
            after(item.value)
        elseif item.error and failed then
            failed(item.error)
        end
        return
    end
    local epoch, finished = ctx.epoch, false
    item.loading, item.error, item.attempted_at = true, nil, os.time()
    publish(ctx)
    local function finish(value, error, auth)
        if finished or ctx.epoch ~= epoch then
            return
        end
        finished = true
        item.loading = false
        if auth then
            -- Invalidate every pending private-data callback on confirmed logout.
            invalidate(ctx)
            ctx.profile = item
            item.value, item.updated_at = nil, nil
            ctx.authError = true
        end
        if value ~= nil then
            sequence += 1
            item.value, item.updated_at, item.version = value, os.time(), sequence
            item.error = nil
            if after then
                after(value)
            end
        else
            item.error = error
            if failed then
                failed(error)
            end
        end
        publish(ctx)
    end
    local started = noctalia.runAsync(argv, function(result)
        if ctx.epoch ~= epoch then
            return
        end
        local raw, error, auth = decodeResult(ctx, result)
        if not raw then
            finish(nil, error, auth)
            return
        end
        local normalized, value = pcall(normalize, raw)
        if not normalized or value == nil then
            finish(nil, "Unexpected response from forge CLI.")
            return
        end
        -- GraphQL returns viewer identity atomically with the contribution calendar.
        if
            (ctx.provider ~= "github" and ctx.provider ~= "gitlab")
            or item == ctx.profile
            or (
                argv[3] == "graphql"
                and raw.data
                and raw.data.viewer
                and raw.data.viewer.login == ctx.account
            )
        then
            finish(value)
            return
        end
        -- gh api has no per-request account selector. Check identity before publishing,
        -- including older inbox pages, to reject detected account switches before caching.
        local checking = noctalia.runAsync(
            ctx.provider == "gitlab" and GitLab.profile(gitlabHost) or GitHub.profile(),
            function(identityResult)
                if ctx.epoch ~= epoch or finished then
                    return
                end
                local identityRaw, identityError, identityAuth = decodeResult(ctx, identityResult)
                if not identityRaw then
                    finish(nil, identityError, identityAuth)
                    return
                end
                local valid, profile = pcall(
                    ctx.provider == "gitlab" and GitLab.normalizeProfile or Data.profile,
                    identityRaw
                )
                if not valid or not profile then
                    finish(nil, "Could not verify forge account.")
                    return
                end
                if profile.id ~= ctx.accountId then
                    finished, item.loading = true, false
                    invalidate(ctx)
                    ctx.account, ctx.accountId, ctx.authError = profile.login, profile.id, false
                    ctx.profile = {
                        value = profile,
                        loading = false,
                        attempted_at = os.time(),
                        updated_at = os.time(),
                    }
                    publish(ctx)
                    if ctx.provider == provider then
                        ensureView(ctx, false)
                    end
                    return
                end
                ctx.profile.value, ctx.profile.error = profile, nil
                ctx.profile.updated_at, ctx.profile.attempted_at = os.time(), os.time()
                finish(value)
            end
        )
        if not checking then
            finish(nil, "Could not verify forge account.")
        end
    end)
    if not started then
        finish(nil, "Could not start forge CLI.")
    end
end
local function notificationPage(ctx, page, force)
    local item = ctx.notifications
    if page > 10 or item.loading or (not force and fresh(item)) then
        return
    end
    local function normalize(raw)
        local incoming = Data.notifications(raw)
        if not incoming then
            return nil
        end
        local result, seen = {}, {}
        if page > 1 then
            for _, row in ipairs(item.value or {}) do
                table.insert(result, row)
                seen[row.id] = true
            end
        end
        for _, row in ipairs(incoming) do
            if not seen[row.id] then
                table.insert(result, row)
                seen[row.id] = true
            end
        end
        return { rows = result, has_more = #incoming == 50 and page < 10 }
    end
    -- The resource value remains a list; pagination metadata advances only on success.
    request(ctx, item, GitHub.notifications(page), normalize, force, function(value)
        item.value, item.page, item.has_more = value.rows, page, value.has_more
    end)
end
local function loadView(ctx, force)
    if ctx.account == "" then
        return
    end
    if ctx.provider == "github" then
        request(ctx, ctx.contributions, GitHub.contributions(), function(raw)
            local value = Data.contributions(raw)
            return value and value.login == ctx.account and value or nil
        end, force)
    end
    if ctx.view == "repositories" then
        request(
            ctx,
            ctx.repositories,
            ctx.provider == "github" and GitHub.repositories()
                or (
                    ctx.provider == "gitlab" and GitLab.repositories(gitlabHost)
                    or Tangled.repositories(ctx.accountId)
                ),
            ctx.provider == "github" and Data.repositories
                or (
                    ctx.provider == "gitlab" and GitLab.normalizeRepositories
                    or Tangled.normalizeRepositories
                ),
            force,
            function(rows)
                if ctx.provider ~= "github" and ctx.repository == "" then
                    ctx.repository = rows[1] and rows[1].name or ""
                end
            end
        )
    elseif ctx.view == "notifications" and ctx.provider == "github" then
        notificationPage(ctx, 1, force)
    elseif ctx.view == "pulls" or ctx.view == "issues" then
        if ctx.provider ~= "github" and ctx.repository == "" then
            publish(ctx)
            return
        end
        local entry = work(ctx)
        if not entry then
            return
        end
        local scope, kind = ctx.repository, ctx.view
        request(
            ctx,
            entry[kind],
            ctx.provider == "github" and GitHub.work(kind, scope)
                or (
                    ctx.provider == "gitlab" and GitLab.work(gitlabHost, kind, scope)
                    or Tangled.work(kind, scope, ctx.accountId)
                ),
            function(raw)
                return ctx.provider == "github" and Data.work(raw)
                    or (
                        ctx.provider == "gitlab" and GitLab.normalizeWork(raw, scope)
                        or Tangled.normalizeWork(raw, scope, kind)
                    )
            end,
            force
        )
    end
    publish(ctx)
end
local function ensureAccount(ctx, force, success, failed)
    ctx.accountWaiters = ctx.accountWaiters or {}
    table.insert(ctx.accountWaiters, { success = success, failed = failed })
    local function notify(error)
        local waiters = ctx.accountWaiters
        ctx.accountWaiters = {}
        for _, waiter in ipairs(waiters) do
            if error then
                if waiter.failed then
                    waiter.failed(error)
                end
            elseif waiter.success then
                waiter.success()
            end
        end
    end
    local cli = ctx.provider == "github" and "gh" or (ctx.provider == "gitlab" and "glab" or "tg")
    if not noctalia.commandExists(cli) then
        ctx.missingCli = true
        ctx.profile.error = "Missing " .. cli .. ". Install it to use this forge."
        publish(ctx)
        notify(ctx.profile.error)
        return
    end
    ctx.missingCli = false
    if ctx.provider == "gitlab" and not gitlabHost then
        ctx.profile.error =
            "Set GitLab instance URL to an HTTPS origin, for example https://gitlab.school.edu."
        publish(ctx)
        notify(ctx.profile.error)
        return
    end
    request(
        ctx,
        ctx.profile,
        ctx.provider == "github" and GitHub.profile()
            or (ctx.provider == "gitlab" and GitLab.profile(gitlabHost) or Tangled.profile()),
        ctx.provider == "github" and Data.profile
            or (ctx.provider == "gitlab" and GitLab.normalizeProfile or Tangled.normalizeProfile),
        force,
        function(profile)
            if ctx.accountId ~= "" and ctx.accountId ~= profile.id then
                invalidate(ctx)
                -- This verified profile belongs to the new account epoch.
                ctx.profile = {
                    value = profile,
                    attempted_at = os.time(),
                    updated_at = os.time(),
                    loading = false,
                }
            end
            ctx.account, ctx.accountId, ctx.authError = profile.login, profile.id, false
            notify()
        end,
        notify
    )
end
ensureView = function(ctx, force)
    ensureAccount(ctx, force, function()
        loadView(ctx, force)
    end)
end
local function validRepository(value)
    if type(value) ~= "string" or #value > 200 then
        return false
    end
    local owner, name = value:match("^([%w][%w%.:%-]*)/([%w_%.%-]+)$")
    return owner ~= nil and name ~= "." and name ~= ".."
end
local function command(value)
    if type(value) ~= "table" then
        return
    end
    actionError = nil
    if
        value.op == "profile"
        and (
            value.provider == "tangled"
            or value.provider == "github"
            or value.provider == "gitlab"
        )
    then
        local ctx = context(value.provider)
        local function failed(message)
            actionError = message
            publish(context(provider))
        end
        ensureAccount(ctx, false, function()
            if not noctalia.commandExists("xdg-open") then
                failed("Missing xdg-open. Install it to open profiles.")
                return
            end
            local host = ctx.provider == "github" and "https://github.com/"
                or (ctx.provider == "gitlab" and (gitlabUrl .. "/") or "https://tangled.org/")
            if not noctalia.runAsync({ "xdg-open", host .. ctx.account }) then
                failed("Could not open forge profile.")
            end
        end, failed)
        publish(context(provider))
    elseif
        value.op == "provider"
        and (
            value.provider == "tangled"
            or value.provider == "github"
            or value.provider == "gitlab"
        )
    then
        provider = value.provider
        local ctx = context(provider)
        publish(ctx)
        ensureView(ctx, false)
    else
        local ctx = context(provider)
        if value.op == "repository" then
            if value.repository == "" and provider ~= "github" then
                return
            end
            if
                value.repository ~= ""
                and not (
                    provider == "gitlab" and GitLab.validRepository(value.repository)
                    or provider ~= "gitlab" and validRepository(value.repository)
                )
            then
                return
            end
            ctx.repository, ctx.view = value.repository, "pulls"
            work(ctx)
            publish(ctx)
            ensureView(ctx, false)
        elseif value.op == "view" then
            local allowed = value.view == "repositories"
                or value.view == "pulls"
                or value.view == "issues"
                or (
                    provider == "github"
                    and (value.view == "overview" or value.view == "notifications")
                )
            if not allowed then
                return
            end
            ctx.view = value.view
            publish(ctx)
            ensureView(ctx, false)
        elseif
            value.op == "notifications_more"
            and provider == "github"
            and ctx.notifications.has_more
        then
            notificationPage(ctx, (ctx.notifications.page or 0) + 1, true)
        elseif value.op == "refresh" then
            ensureView(ctx, true)
        end
    end
end
noctalia.state.watch("forges.command", command)
noctalia.setUpdateInterval(interval() * 1000)
ensureView(context(provider), false)
function update()
    ensureView(context(provider), false)
end
function onConfigChanged()
    noctalia.setUpdateInterval(interval() * 1000)
    local nextUrl, nextHost = GitLab.instance(noctalia.getConfig("gitlab_url"))
    if nextUrl ~= gitlabUrl then
        invalidate(context("gitlab"))
        context("gitlab").profile = resource()
        context("gitlab").view = "repositories"
        context("gitlab").accountWaiters = {}
        context("gitlab").authError = false
        gitlabUrl, gitlabHost = nextUrl, nextHost
    end
    local nextDefault = defaultProvider()
    if configuredProvider ~= nextDefault then
        configuredProvider, provider = nextDefault, nextDefault
    end
    publish(context(provider))
    ensureView(context(provider), false)
end
function onIpc(event)
    if event == "refresh" then
        ensureView(context(provider), true)
    end
end
