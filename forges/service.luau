--!nonstrict
local GitHub = require("./lib/github.luau")
local Data = require("./lib/data.luau")
local Tangled = require("./lib/tangled.luau")

local function defaultProvider()
    return noctalia.getConfig("provider") == "github" and "github" or "tangled"
end
local provider = defaultProvider()
local configuredProvider = provider
local generation = 0
local inFlight = false
local scopes = { tangled = "", github = "" }
local snapshot

local function emptySnapshot()
    return {
        provider = provider,
        account = "",
        repository = scopes[provider],
        repositories = {},
        pulls = {},
        issues = {},
        notifications = {},
        errors = {},
        status = "loading",
        stale = false,
    }
end
local function publish()
    noctalia.state.set("forges.snapshot", snapshot)
end
local function interval()
    local value = tonumber(noctalia.getConfig("refresh_interval_minutes")) or 15
    if value ~= value or math.abs(value) == math.huge then
        value = 15
    end
    return math.clamp(value, 5, 60) * 60000
end
local function validRepository(value)
    if type(value) ~= "string" or #value > 200 then
        return false
    end
    local owner, name = value:match("^([%w][%w%.:%-]*)/([%w_%.%-]+)$")
    return owner ~= nil and name ~= "." and name ~= ".."
end
local function refresh(force)
    if inFlight and not force then
        return
    end
    generation += 1
    local version, forge = generation, provider
    local cli = forge == "tangled" and "tg" or "gh"
    local previous = snapshot
    local nextSnapshot = table.clone(snapshot)
    nextSnapshot.errors = {}
    nextSnapshot.status = "loading"
    nextSnapshot.stale = previous.updated_at ~= nil
    snapshot = nextSnapshot
    if not noctalia.commandExists(cli) then
        inFlight = false
        snapshot.status = "missing_cli"
        snapshot.errors.account = "Missing " .. cli .. ". Install it to use this forge."
        publish()
        return
    end
    inFlight = true
    publish()

    -- Every callback is bound to a provider/scope generation. Late work is ignored.
    local function request(argv, normalize, callback)
        local completed = false
        local function finish(value, error, errorKind)
            if completed or generation ~= version then
                return
            end
            completed = true
            callback(value, error, errorKind)
        end
        local started = noctalia.runAsync(argv, function(result)
            if generation ~= version then
                return
            end
            if result.exitCode ~= 0 then
                local stderr = string.lower(result.stderr or "")
                local auth = stderr:find("401", 1, true)
                    or stderr:find("not logged", 1, true)
                    or stderr:find("authentication", 1, true)
                    or stderr:find("login required", 1, true)
                    or stderr:find("gh auth login", 1, true)
                    or stderr:find("tg auth login", 1, true)
                finish(
                    nil,
                    "Request failed. Check network access and " .. cli .. " authentication.",
                    auth and "auth" or "request"
                )
                return
            end
            local ok, raw = pcall(noctalia.json.decode, result.stdout or "")
            if not ok or type(raw) ~= "table" then
                finish(nil, "Invalid JSON returned by " .. cli .. ".")
                return
            end
            local normalized, value = pcall(normalize, raw)
            if not normalized or value == nil then
                finish(
                    nil,
                    "Unexpected response from " .. cli .. ".",
                    raw.authenticated == false and "auth" or "request"
                )
                return
            end
            finish(value)
        end)
        if not started then
            finish(nil, "Could not start " .. cli .. ".")
        end
    end
    local function done()
        inFlight = false
        snapshot.status = next(snapshot.errors) and "partial" or "ready"
        snapshot.stale = next(snapshot.errors) ~= nil and previous.updated_at ~= nil
        if not next(snapshot.errors) then
            snapshot.updated_at = os.time()
        end
        publish()
    end
    local profileCommand = forge == "tangled" and Tangled.profile() or GitHub.profile()
    local normalizeProfile = forge == "tangled" and Tangled.normalizeProfile or Data.profile
    request(profileCommand, normalizeProfile, function(profile, error, errorKind)
        if not profile then
            if errorKind ~= "auth" and previous.account ~= "" then
                snapshot = table.clone(previous)
                snapshot.status, snapshot.stale = "partial", true
                snapshot.errors = { account = error }
            else
                -- Never retain account data after an authentication failure.
                snapshot = emptySnapshot()
                snapshot.status = "auth_error"
                local login = cli == "tg" and "tg auth login <handle>" or "gh auth login"
                snapshot.errors.account = error .. " Sign in with " .. login .. "."
            end
            inFlight = false
            publish()
            return
        end
        if previous.account ~= "" and previous.account ~= profile.login then
            scopes[forge] = ""
            snapshot = emptySnapshot()
            previous = snapshot
        end
        snapshot.account = profile.login
        local repoCommand = forge == "tangled" and Tangled.repositories() or GitHub.repositories()
        local normalizeRepos = forge == "tangled" and Tangled.normalizeRepositories
            or Data.repositories
        request(repoCommand, normalizeRepos, function(repositories, repoError)
            if repositories then
                snapshot.repositories = repositories
            else
                snapshot.errors.repositories = repoError
            end
            local repository = scopes[forge]
            if forge == "tangled" and repository == "" then
                repository = snapshot.repositories[1] and snapshot.repositories[1].name or ""
            end
            scopes[forge] = repository
            -- Last-good rows only belong to the same account AND repository scope.
            if snapshot.repository ~= repository then
                snapshot.pulls, snapshot.issues = {}, {}
                snapshot.updated_at = nil
            end
            snapshot.repository = repository
            local pending = forge == "github" and 3 or (repository ~= "" and 2 or 0)
            if pending == 0 then
                done()
                return
            end
            local function completed(key, value, workError)
                if value then
                    snapshot[key] = value
                else
                    snapshot.errors[key] = workError
                end
                pending -= 1
                if pending == 0 then
                    done()
                end
            end
            for _, kind in ipairs({ "pulls", "issues" }) do
                local command = forge == "tangled" and Tangled.work(kind, repository)
                    or GitHub.work(kind, repository)
                local function normalize(raw)
                    if forge == "tangled" then
                        return Tangled.normalizeWork(raw, repository, kind)
                    end
                    return Data.work(raw)
                end
                request(command, normalize, function(value, workError)
                    completed(kind, value, workError)
                end)
            end
            if forge == "github" then
                request(
                    GitHub.notifications(),
                    Data.notifications,
                    function(value, notificationError)
                        completed("notifications", value, notificationError)
                    end
                )
            end
        end)
    end)
end
local function command(value)
    if type(value) ~= "table" then
        return
    end
    if value.op == "provider" and (value.provider == "tangled" or value.provider == "github") then
        if provider == value.provider then
            return
        end
        provider = value.provider
        snapshot = emptySnapshot()
        refresh(true)
    elseif value.op == "repository" then
        if value.repository == "" and provider ~= "github" then
            return
        end
        if value.repository ~= "" and not validRepository(value.repository) then
            return
        end
        if snapshot.repository == value.repository then
            return
        end
        scopes[provider] = value.repository
        snapshot.pulls, snapshot.issues = {}, {}
        snapshot.repository = value.repository
        snapshot.updated_at = nil
        refresh(true)
    elseif value.op == "refresh" then
        refresh(false)
    end
end
snapshot = emptySnapshot()
noctalia.state.watch("forges.command", command)
noctalia.setUpdateInterval(interval())
refresh(false)
function update()
    refresh(false)
end
function onConfigChanged()
    noctalia.setUpdateInterval(interval())
    local nextDefault = defaultProvider()
    if configuredProvider ~= nextDefault then
        configuredProvider = nextDefault
        provider = nextDefault
        snapshot = emptySnapshot()
    end
    refresh(true)
end
function onIpc(event)
    if event == "refresh" then
        refresh(false)
    end
end
