--!nonstrict

local inFlight = false
local speedHistory = {}
local lastHistory = {}

local function number(value)
    if type(value) == "number" and value == value and math.abs(value) ~= math.huge then
        return math.max(0, value)
    end
    return 0
end

local function publish(snapshot, errorMessage)
    local downloads = snapshot.items or {}
    if errorMessage then
        -- Do not connect a recovered graph across an unknown/offline interval.
        speedHistory = {}
    else
        lastHistory = snapshot.history or {}
        local speed = 0
        for _, item in ipairs(downloads) do
            speed = speed + item.speed
        end
        speedHistory[#speedHistory + 1] = speed
        if #speedHistory > 60 then
            table.remove(speedHistory, 1)
        end
    end
    noctalia.state.set("downloads", {
        items = downloads,
        active = snapshot.active or {},
        history = table.clone(lastHistory),
        error = errorMessage or "",
        speedHistory = table.clone(speedHistory),
    })
end

local function normalize(raw)
    if type(raw) ~= "table" then
        return nil
    end
    local items, active, history = {}, {}, {}
    local count = 0
    for key, item in pairs(raw) do
        count = count + 1
        if
            type(key) ~= "number"
            or key < 1
            or key % 1 ~= 0
            or type(item) ~= "table"
            or type(item.status) ~= "string"
            or type(item.id) ~= "string"
        then
            return nil
        end
    end
    if count ~= #raw then
        return nil
    end
    for _, item in ipairs(raw) do
        local terminal = item.status == "completed" or item.status == "error"
        if
            terminal
            or item.status == "downloading"
            or item.status == "paused"
            or item.status == "queued"
        then
            local total = number(item.total_size)
            local downloaded = number(item.downloaded)
            local entry = {
                id = item.id,
                status = item.status,
                addedAt = number(item.added_at),
                filename = type(item.filename) == "string" and string.sub(item.filename, 1, 512)
                    or "Download",
                progress = total > 0 and math.clamp(downloaded / total, 0, 1) or nil,
                total = total,
                downloaded = downloaded,
                speed = item.status == "downloading" and number(item.speed) or 0,
            }
            if terminal then
                history[#history + 1] = entry
            else
                active[#active + 1] = entry
                if item.status == "downloading" then
                    items[#items + 1] = entry
                end
            end
        end
    end
    table.sort(history, function(a, b)
        if a.addedAt == b.addedAt then
            return a.id < b.id
        end
        return a.addedAt > b.addedAt
    end)
    while #history > 100 do
        table.remove(history)
    end
    return { items = items, active = active, history = history }
end

local function refresh()
    if inFlight then
        return
    end
    local path = noctalia.getConfig("surgePath")
    if type(path) ~= "string" or path == "" then
        path = "surge"
    end
    local host = noctalia.getConfig("host")
    if type(host) ~= "string" or host == "" then
        host = "127.0.0.1:1700"
    end
    inFlight = true
    -- An explicit host prevents Surge from reporting stale database entries as live downloads.
    -- Surge owns token discovery; credentials never enter plugin settings or shared state.
    local accepted = noctalia.runAsync(
        { "timeout", "5s", noctalia.expandPath(path), "ls", "--json", "--host", host },
        function(result)
            inFlight = false
            if
                type(result) ~= "table"
                or result.exitCode ~= 0
                or result.timedOut == true
                or result.stdoutTruncated == true
            then
                publish({}, "Surge server unavailable")
                return
            end
            local ok, raw = pcall(noctalia.json.decode, result.stdout or "")
            local items = ok and normalize(raw) or nil
            if items == nil then
                publish({}, "Invalid Surge response")
                return
            end
            publish(items)
        end,
        6000
    )
    if accepted == false then
        inFlight = false
        publish({}, "Could not run Surge")
    end
end

noctalia.state.watch("command", function(value)
    if type(value) == "table" and value.action == "refresh" then
        refresh()
    end
end)

function update()
    local interval = tonumber(noctalia.getConfig("refreshIntervalSec")) or 2
    if interval ~= interval or math.abs(interval) == math.huge then
        interval = 2
    end
    noctalia.setUpdateInterval(math.clamp(interval, 1, 60) * 1000)
    refresh()
end

function onIpc(event, _payload)
    if event == "refresh" then
        refresh()
    end
end

update()
