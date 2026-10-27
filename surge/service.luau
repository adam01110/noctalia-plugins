--!nonstrict

local inFlight = false
local speedHistory = {}

local function number(value)
    if type(value) == "number" and value == value and math.abs(value) ~= math.huge then
        return math.max(0, value)
    end
    return 0
end

local function publish(downloads, errorMessage)
    if errorMessage then
        -- Do not connect a recovered graph across an unknown/offline interval.
        speedHistory = {}
    else
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
        error = errorMessage or "",
        speedHistory = table.clone(speedHistory),
    })
end

local function normalize(raw)
    if type(raw) ~= "table" then
        return nil
    end
    local items = {}
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
        -- Paused, queued, failed, and completed entries must not occupy the bar.
        if item.status == "downloading" then
            local total = number(item.total_size)
            local downloaded = number(item.downloaded)
            items[#items + 1] = {
                id = item.id,
                filename = type(item.filename) == "string" and string.sub(item.filename, 1, 512)
                    or "Download",
                progress = total > 0 and math.clamp(downloaded / total, 0, 1) or nil,
                total = total,
                downloaded = downloaded,
                speed = number(item.speed),
            }
        end
    end
    return items
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
