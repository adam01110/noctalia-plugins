-- Native monthly activity, adapted from Tangled's ProfileActivityChart.svelte (MIT).
-- See ../TANGLED-LICENSE for the original copyright and license.
local Activity = {}
Activity.monthLabels =
    { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
Activity.metrics = { "pulls", "commits", "repos", "issues" }
function Activity.months()
    local today = os.date("!*t", os.time())
    local current = today.year * 12 + today.month - 1
    local months = {}
    for ordinal = current - 5, current do
        local year, month = math.floor(ordinal / 12), ordinal % 12 + 1
        local date = string.format("%04d-%02d", year, month)
        table.insert(months, {
            date = date,
            label = Activity.monthLabels[month],
            values = {},
            lowerBounds = {},
        })
    end
    return months
end
function Activity.monthEnd(months, index)
    if not months[index + 1] then
        return os.date("!%Y-%m-%dT%H:%M:%SZ", os.time())
    end
    local year, month = months[index + 1].date:match("^(%d%d%d%d)%-(%d%d)$")
    -- Luau's os.time(table) uses UTC, unlike Lua. End before the inclusive next midnight.
    return os.date(
        "!%Y-%m-%dT%H:%M:%SZ",
        os.time({ year = tonumber(year), month = tonumber(month), day = 1, hour = 0 }) - 1
    )
end
function Activity.count(n)
    return type(n) == "number" and n == n and n >= 0 and n <= 1000000000 and n % 1 == 0
end
function Activity.fromCalendar(data)
    if data.activity then
        return data.activity
    end
    local months = Activity.months()
    local byDate = {}
    for _, month in ipairs(months) do
        byDate[month.date] = month
    end
    if data.granularity == "month" then
        for _, month in ipairs(data.months or {}) do
            local target = byDate[month.date]
            if target then
                target.values.commits = month.count
            end
        end
        return { months = months, note = "Public commits · other metrics unavailable" }
    end
    local first, last = data.firstDate or "", data.lastDate or ""
    for _, month in ipairs(months) do
        if month.date >= first:sub(1, 7) and month.date <= last:sub(1, 7) then
            month.values.contributions = 0
        end
    end
    for _, week in ipairs(data.weeks or {}) do
        for _, day in ipairs(week.days) do
            if day then
                local month = byDate[day.date:sub(1, 7)]
                if month and month.values.contributions ~= nil then
                    month.values.contributions += day.count
                end
            end
        end
    end
    return {
        months = months,
        aggregate = true,
        note = "Contribution totals · commits, PRs/MRs, issues and new repositories unavailable separately",
    }
end
function Activity.github(raw)
    local viewer = raw.data and raw.data.viewer
    if not viewer then
        return nil
    end
    local months = Activity.months()
    local fields = {
        commits = "totalCommitContributions",
        pulls = "totalPullRequestContributions",
        issues = "totalIssueContributions",
        repos = "totalRepositoryContributions",
    }
    for i, month in ipairs(months) do
        local source = viewer["activity" .. tostring(i)]
        if
            type(source) ~= "table"
            or type(source.startedAt) ~= "string"
            or source.startedAt:sub(1, 10) ~= month.date .. "-01"
        then
            return nil
        end
        for metric, field in pairs(fields) do
            if not Activity.count(source[field]) then
                return nil
            end
            month.values[metric] = source[field]
        end
    end
    return {
        months = months,
        note = "GitHub contribution credit",
    }
end
local TOP, BOTTOM, GAP = 20, 164, 28
local function clusterTop(cluster)
    local span = (#cluster.metrics - 1) * GAP
    return math.clamp(cluster.sum / #cluster.metrics, TOP, BOTTOM - span)
end
function Activity.layout(activity)
    local metrics = activity.aggregate and { "contributions" } or Activity.metrics
    local points, columns, raw = {}, {}, {}
    for i = 1, 6 do
        columns[i] = { left = (i - 1) * 68, width = i == 6 and 208 or 68 }
    end
    for _, metric in ipairs(metrics) do
        local low, high = math.huge, -math.huge
        points[metric], raw[metric] = {}, {}
        for _, month in ipairs(activity.months) do
            local n = month.values[metric]
            if n ~= nil then
                low, high = math.min(low, n), math.max(high, n)
            end
        end
        for i, month in ipairs(activity.months) do
            local n = month.values[metric]
            -- Unknown metrics keep a readable label, but never acquire a zero-valued line.
            raw[metric][i] = n ~= nil
                    and high > low
                    and (BOTTOM - (n - low) / (high - low) * (BOTTOM - TOP))
                or (TOP + BOTTOM) / 2
        end
    end
    for i, month in ipairs(activity.months) do
        local sorted = {}
        for order, metric in ipairs(metrics) do
            table.insert(sorted, { metric = metric, y = raw[metric][i], order = order })
        end
        table.sort(sorted, function(a, b)
            return a.y < b.y or (a.y == b.y and a.order < b.order)
        end)
        local clusters = {}
        for _, point in ipairs(sorted) do
            table.insert(clusters, { metrics = { point.metric }, sum = point.y })
        end
        local index = 2
        while index <= #clusters do
            local previous, current = clusters[index - 1], clusters[index]
            if clusterTop(previous) + #previous.metrics * GAP <= clusterTop(current) then
                index += 1
            else
                local merged = {
                    metrics = {},
                    sum = previous.sum + current.sum - #previous.metrics * #current.metrics * GAP,
                }
                for _, metric in ipairs(previous.metrics) do
                    table.insert(merged.metrics, metric)
                end
                for _, metric in ipairs(current.metrics) do
                    table.insert(merged.metrics, metric)
                end
                clusters[index - 1] = merged
                table.remove(clusters, index)
                index = math.max(index - 1, 2)
            end
        end
        for _, cluster in ipairs(clusters) do
            for offset, metric in ipairs(cluster.metrics) do
                points[metric][i] = {
                    x = columns[i].left + 8,
                    y = clusterTop(cluster) + (offset - 1) * GAP,
                    value = month.values[metric],
                    lowerBound = month.lowerBounds[metric] == true,
                }
            end
        end
    end
    return { width = 548, height = 210, columns = columns, points = points, metrics = metrics }
end
local NAMES = {
    pulls = "pull requests",
    commits = "commits",
    repos = "new repos",
    issues = "issues",
    contributions = "contributions",
}
function Activity.metricName(metric, provider)
    return metric == "pulls" and provider == "gitlab" and "merge requests" or NAMES[metric]
end
local function compact(n)
    if n >= 1000000000 then
        return string.format("%.1fb", n / 1000000000)
    end
    if n >= 1000000 then
        return string.format("%.1fm", n / 1000000)
    end
    if n >= 10000 then
        return string.format("%.0fk", n / 1000)
    end
    if n >= 1000 then
        return string.format("%.1fk", n / 1000)
    end
    return tostring(n)
end
function Activity.valueText(value, lowerBound, short)
    if value == nil then
        return "—"
    end
    return (short and compact(value) or tostring(value)) .. (lowerBound and "+" or "")
end
function Activity.detail(activity, index, provider)
    local month = activity.months[index]
    local values = { month.date }
    for _, metric in ipairs(activity.aggregate and { "contributions" } or Activity.metrics) do
        table.insert(
            values,
            Activity.valueText(month.values[metric], month.lowerBounds[metric], false)
                .. " "
                .. Activity.metricName(metric, provider)
        )
    end
    return table.concat(values, " · ")
end
-- Sample Tangled's midpoint-control cubic at uniform x positions for ui.graph.
function Activity.curveValues(first, last, height)
    local start = (1 - first.y / height - 0.06) / 0.88
    -- API34 starts its visible shader span at sample 2; keep the first anchor in that slot.
    local values = { start, start }
    for step = 0, 16 do
        local x = step / 16
        local t = x
        for _ = 1, 5 do
            local position = 1.5 * t - 1.5 * t * t + t * t * t
            t -= (position - x) / (1.5 - 3 * t + 3 * t * t)
        end
        local y = first.y + (last.y - first.y) * (3 * t * t - 2 * t * t * t)
        -- API34's shader reserves 6% at this plot height/line width; align native labels to it.
        table.insert(values, (1 - y / height - 0.06) / 0.88)
    end
    return values
end
function Activity.comparison(activity, index, metric)
    local current, previous = activity.months[index], activity.months[index - 1]
    if current.values[metric] == nil then
        return "Not reported for this month", "on_surface_variant"
    end
    if current.lowerBounds[metric] then
        return "Lower bound · exact change unavailable", "on_surface_variant"
    end
    if not previous then
        return "First month in this window", "on_surface_variant"
    end
    if previous.values[metric] == nil or previous.lowerBounds[metric] then
        return "Previous month incomplete · change unavailable", "on_surface_variant"
    end
    local delta = current.values[metric] - previous.values[metric]
    local suffix = " vs " .. previous.label
    if current.date == os.date("!%Y-%m", os.time()) then
        suffix ..= " (full month)"
    end
    if delta == 0 then
        return "No change" .. suffix, "on_surface_variant"
    end
    return (delta > 0 and "↗ +" or "↘ ") .. tostring(delta) .. suffix,
        delta > 0 and "primary" or "error"
end
return Activity
