-- Tangled-style activity layout, adapted from tangled-core's profileActivityChart.ts (MIT).
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
        note = "GitHub contribution credit · each metric scaled independently",
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
local ICONS = {
    commits = '<path d="M0 6h3m6 0h3"/><circle cx="6" cy="6" r="3"/>',
    pulls = '<circle cx="3" cy="2" r="1.5"/><circle cx="3" cy="10" r="1.5"/><path d="M3 4v4m4-6h1q2 0 2 2v4m-3-6 2-2m-2 2 2 2"/><circle cx="10" cy="10" r="1.5"/>',
    issues = '<circle cx="6" cy="6" r="5"/><circle cx="6" cy="6" r="0.7"/>',
    repos = '<path d="M2 1h8v10H2zM4 6h4M6 4v4"/>',
    contributions = '<path d="M0 10h2V6h3V2h3v6h4"/>',
}
function Activity.svg(activity, colors, provider)
    local layout = Activity.layout(activity)
    local parts = {
        '<svg xmlns="http://www.w3.org/2000/svg" width="548" height="210" viewBox="0 0 548 210">',
        '<rect width="548" height="210" fill="' .. colors.background .. '"/>',
        '<rect x="340" width="208" height="210" fill="' .. colors.current .. '"/>',
    }
    for i = 2, 6 do
        table.insert(
            parts,
            string.format(
                '<path d="M%d 0V210" stroke="%s" stroke-opacity="0.45"/>',
                layout.columns[i].left,
                colors.border
            )
        )
    end
    for _, metric in ipairs(layout.metrics) do
        local points = layout.points[metric]
        for i = 1, 5 do
            local point, following = points[i], points[i + 1]
            if point.value ~= nil and following.value ~= nil then
                local color = following.value >= point.value and colors.rising or colors.falling
                local dashed = (point.lowerBound or following.lowerBound)
                        and ' stroke-dasharray="3 3"'
                    or ""
                table.insert(
                    parts,
                    string.format(
                        '<path d="M%.2f %.2fC%.2f %.2f %.2f %.2f %.2f %.2f" fill="none" stroke="%s" stroke-opacity="0.38"%s/>',
                        point.x,
                        point.y,
                        (point.x + following.x) / 2,
                        point.y,
                        (point.x + following.x) / 2,
                        following.y,
                        following.x,
                        following.y,
                        color,
                        dashed
                    )
                )
            end
        end
        local first, last = points[1], points[6]
        if first.value ~= nil then
            table.insert(
                parts,
                string.format(
                    '<path d="M0 %.2fH%.2f" stroke="%s" stroke-opacity="0.3"/>',
                    first.y,
                    first.x,
                    colors.rising
                )
            )
        end
        if last.value ~= nil then
            table.insert(
                parts,
                string.format(
                    '<path d="M%.2f %.2fH548" stroke="%s" stroke-opacity="0.3"/>',
                    last.x,
                    last.y,
                    colors.rising
                )
            )
        end
    end
    for i, month in ipairs(activity.months) do
        local current = i == 6
        local background = current and colors.current or colors.background
        for _, metric in ipairs(layout.metrics) do
            local point = layout.points[metric][i]
            local text = Activity.valueText(point.value, point.lowerBound, not current)
            if current then
                text ..= " " .. Activity.metricName(metric, provider)
            end
            local width = current and math.min(198, #text * 6.4 + 30) or 62
            table.insert(
                parts,
                string.format(
                    '<rect x="%.2f" y="%.2f" width="%.2f" height="22" fill="%s"/>',
                    point.x - 3,
                    point.y - 11,
                    width,
                    background
                )
            )
            table.insert(
                parts,
                string.format(
                    '<g transform="translate(%.2f %.2f)" stroke="%s" fill="none" stroke-width="1">%s</g>',
                    point.x,
                    point.y - 6,
                    colors.text,
                    ICONS[metric]
                )
            )
            table.insert(
                parts,
                string.format(
                    '<text x="%.2f" y="%.2f" font-family="sans-serif" font-size="11" fill="%s">%s</text>',
                    point.x + 17,
                    point.y + 4,
                    colors.text,
                    text
                )
            )
            local previous = i > 1 and layout.points[metric][i - 1]
            if
                previous
                and point.value ~= nil
                and previous.value ~= nil
                and not point.lowerBound
                and not previous.lowerBound
            then
                local arrow = point.value > previous.value and "↗"
                    or (point.value < previous.value and "↘" or "–")
                table.insert(
                    parts,
                    string.format(
                        '<text x="%.2f" y="%.2f" font-family="sans-serif" font-size="10" fill="%s">%s</text>',
                        point.x + (current and (22 + #text * 6.4) or 49),
                        point.y + 4,
                        point.value >= previous.value and colors.rising or colors.falling,
                        arrow
                    )
                )
            end
        end
        table.insert(
            parts,
            string.format(
                '<text x="%d" y="198" font-family="sans-serif" font-size="11" fill="%s">%s%s</text>',
                layout.columns[i].left + 8,
                colors.text,
                month.label,
                current and " · now" or ""
            )
        )
    end
    table.insert(parts, "</svg>")
    return table.concat(parts)
end
return Activity
