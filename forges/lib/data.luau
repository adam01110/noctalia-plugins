-- Adapted from Shangshui0302's GitHub Kanban (MIT).
local Data = {}
function Data.profile(raw)
    if type(raw.login) ~= "string" or raw.login == "" then
        return nil
    end
    return { id = tostring(raw.id or raw.login), login = raw.login, name = raw.name or raw.login }
end
function Data.repositories(raw)
    if raw.message ~= nil then
        return nil
    end
    local out = {}
    for i, item in ipairs(raw) do
        if i > 50 then
            break
        end
        if type(item.full_name) == "string" then
            table.insert(out, {
                name = item.full_name,
                description = item.description or "",
                url = item.html_url or ("https://github.com/" .. item.full_name),
                updatedAt = item.updated_at or "",
            })
        end
    end
    return out
end
function Data.work(raw)
    if type(raw.items) ~= "table" then
        return nil
    end
    local out = {}
    for i, item in ipairs(raw.items) do
        if i > 30 then
            break
        end
        table.insert(out, {
            id = tostring(item.number or ""),
            title = item.title or "",
            repository = (item.repository_url or ""):match("repos/(.+)$") or "",
            author = type(item.user) == "table" and item.user.login or "",
            state = item.state or "open",
            url = item.html_url or "",
            updatedAt = item.updated_at or "",
        })
    end
    return out
end
function Data.notifications(raw)
    if raw.message ~= nil then
        return nil
    end
    local out = {}
    for i, item in ipairs(raw) do
        if i > 50 then
            break
        end
        local subject, repo = item.subject or {}, item.repository or {}
        local number = (subject.url or ""):match("/issues/(%d+)$")
            or (subject.url or ""):match("/pulls/(%d+)$")
        local path = subject.type == "PullRequest" and "pull" or "issues"
        table.insert(out, {
            id = tostring(item.id or ""),
            title = subject.title or "",
            repository = repo.full_name or "",
            author = item.reason or "",
            state = item.unread and "unread" or "read",
            updatedAt = item.updated_at or "",
            url = number
                    and ("https://github.com/" .. (repo.full_name or "") .. "/" .. path .. "/" .. number)
                or "https://github.com/notifications",
        })
    end
    return out
end
-- Adapted from the upstream contribution calendar; keep actual calendar slots.
function Data.contributions(raw, todayDate)
    if type(raw.errors) == "table" and next(raw.errors) ~= nil then
        return nil
    end
    local viewer = raw.data and raw.data.viewer
    local calendar = viewer
        and viewer.contributionsCollection
        and viewer.contributionsCollection.contributionCalendar
    if
        type(calendar) ~= "table"
        or type(calendar.weeks) ~= "table"
        or type(viewer.login) ~= "string"
    then
        return nil
    end
    local function count(value)
        if type(value) ~= "number" or value ~= value or value < 0 or value > 1000000000 then
            return nil
        end
        return math.floor(value)
    end
    local total = count(calendar.totalContributions)
    if total == nil or #calendar.weeks > 54 then
        return nil
    end
    local levels = {
        NONE = 0,
        FIRST_QUARTILE = 1,
        SECOND_QUARTILE = 2,
        THIRD_QUARTILE = 3,
        FOURTH_QUARTILE = 4,
    }
    local weeks, days = {}, {}
    for _, week in ipairs(calendar.weeks) do
        if type(week.contributionDays) ~= "table" or #week.contributionDays > 7 then
            return nil
        end
        local slots = { false, false, false, false, false, false, false }
        for index, day in ipairs(week.contributionDays) do
            local n = count(day.contributionCount)
            local weekday = day.weekday
            if weekday == nil then
                weekday = index - 1
            end
            if
                n == nil
                or type(day.date) ~= "string"
                or not day.date:match("^%d%d%d%d%-%d%d%-%d%d$")
                or type(weekday) ~= "number"
                or weekday % 1 ~= 0
                or weekday < 0
                or weekday > 6
                or levels[day.contributionLevel] == nil
                or slots[weekday + 1] ~= false
            then
                return nil
            end
            slots[weekday + 1] =
                { date = day.date, count = n, level = levels[day.contributionLevel] }
        end
        for _, day in ipairs(slots) do
            if day then
                table.insert(days, day)
            end
        end
        table.insert(weeks, { days = slots })
    end
    if #days == 0 then
        return nil
    end
    local today, todayCount, current, best = todayDate or os.date("!%Y-%m-%d"), 0, 0, 0
    for _, day in ipairs(days) do
        if day.date == today then
            todayCount = day.count
        end
        if day.count > 0 then
            current += 1
            best = math.max(best, current)
        else
            current = 0
        end
    end
    local last = #days
    if days[last].date == today and days[last].count == 0 then
        last -= 1
    end
    local streak = 0
    while last > 0 and days[last].count > 0 do
        streak += 1
        last -= 1
    end
    return {
        login = viewer.login,
        total = total,
        weeks = weeks,
        today = todayCount,
        currentStreak = streak,
        bestStreak = best,
        firstDate = days[1].date,
        lastDate = days[#days].date,
    }
end
function Data.dailyContributions(counts, login, utcOffset)
    if type(counts) ~= "table" or type(login) ~= "string" then
        return nil
    end
    local entries = 0
    for date, n in pairs(counts) do
        entries += 1
        if entries > 367 then
            return nil
        end
        if
            type(date) ~= "string"
            or not date:match("^%d%d%d%d%-%d%d%-%d%d$")
            or type(n) ~= "number"
            or n ~= n
            or n < 0
            or n % 1 ~= 0
            or n > 1000000000
        then
            return nil
        end
        local year, month, day = date:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
        local valid, timestamp = pcall(
            os.time,
            { year = tonumber(year), month = tonumber(month), day = tonumber(day), hour = 0 }
        )
        if not valid or os.date("!%Y-%m-%d", timestamp) ~= date then
            return nil
        end
    end
    utcOffset = utcOffset or 0
    if type(utcOffset) ~= "number" or utcOffset ~= utcOffset or math.abs(utcOffset) > 86400 then
        return nil
    end
    local today = os.date("!*t", os.time() + utcOffset)
    local midnight = os.time({ year = today.year, month = today.month, day = today.day, hour = 0 })
    local priorDay = today.day
    if today.month == 2 and priorDay == 29 then
        priorDay = 28
    end
    local first = os.time({ year = today.year - 1, month = today.month, day = priorDay, hour = 0 })
    local weeks, week, total = {}, nil, 0
    local levels =
        { "NONE", "FIRST_QUARTILE", "SECOND_QUARTILE", "THIRD_QUARTILE", "FOURTH_QUARTILE" }
    for timestamp = first, midnight, 86400 do
        local date = os.date("!%Y-%m-%d", timestamp)
        local weekday = tonumber(os.date("!%w", timestamp))
        local n = counts[date] or 0
        if type(n) ~= "number" or n ~= n or n < 0 or n % 1 ~= 0 or n > 1000000000 then
            return nil
        end
        if not week or weekday == 0 then
            week = { contributionDays = {} }
            table.insert(weeks, week)
        end
        local level = n == 0 and 1 or (n < 3 and 2 or (n < 6 and 3 or (n < 10 and 4 or 5)))
        table.insert(week.contributionDays, {
            date = date,
            weekday = weekday,
            contributionCount = n,
            contributionLevel = levels[level],
        })
        total += n
    end
    return Data.contributions({
        data = {
            viewer = {
                login = login,
                contributionsCollection = {
                    contributionCalendar = { totalContributions = total, weeks = weeks },
                },
            },
        },
    }, os.date("!%Y-%m-%d", midnight))
end
return Data
