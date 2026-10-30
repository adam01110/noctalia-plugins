local systemDate, systemTime = os.date, os.time
local os = {
    date = systemDate,
    time = function(value)
        return value and systemTime(value) or 1709251200
    end, -- 2024-03-01T00:00:00Z
}
local Activity = (function()
    -- ACTIVITY_SOURCE
end)()
local months = Activity.months()
assert(months[1].date == "2023-10" and months[1].label == "Oct")
assert(months[5].date == "2024-02" and months[5].label == "Feb")
assert(Activity.monthEnd(months, 5) == "2024-02-29T23:59:59Z")
assert(Activity.monthEnd(months, 4) == "2024-01-31T23:59:59Z")
assert(Activity.monthEnd(months, 6) == "2024-03-01T00:00:00Z")
assert(
    Activity.monthEnd({ { date = "2100-02" }, { date = "2100-03" } }, 1) == "2100-02-28T23:59:59Z"
)
assert(
    Activity.monthEnd({ { date = "2000-02" }, { date = "2000-03" } }, 1) == "2000-02-29T23:59:59Z"
)
for i, month in ipairs(months) do
    month.values = { commits = 700 - i * 100, pulls = i * 10, repos = i % 3, issues = 5 }
end
months[2].lowerBounds.pulls = true
months[3].values.repos = nil
local activity = { months = months }
local layout = Activity.layout(activity)
assert(layout.width == 548 and layout.height == 210 and #layout.metrics == 4)
for i = 1, 6 do
    local points = {}
    for _, metric in ipairs(layout.metrics) do
        table.insert(points, layout.points[metric][i])
    end
    table.sort(points, function(a, b)
        return a.y < b.y
    end)
    for j = 2, #points do
        assert(points[j].y - points[j - 1].y >= 28)
    end
end
for _, metric in ipairs(layout.metrics) do
    for i = 1, 5 do
        local first, last = layout.points[metric][i], layout.points[metric][i + 1]
        local values = Activity.curveValues(first, last, layout.height)
        assert(#values == 19)
        for _, value in ipairs(values) do
            assert(value >= 0 and value <= 1)
        end
        local function nativeY(value)
            return layout.height * (1 - (0.06 + 0.88 * value))
        end
        assert(math.abs(nativeY(values[3]) - first.y) < 0.000001)
        assert(math.abs(nativeY(values[19]) - last.y) < 0.000001)
        for _, scale in ipairs({ 0.5, 1, 1.5, 2 }) do
            local pad =
                math.min(0.18, math.max((scale * 0.5 + 2) / layout.height / scale + 0.04, 0.06))
            for _, sample in ipairs({ 3, 19 }) do
                local nativeByte = math.floor(values[sample] * 255) / 255
                local rendered = layout.height * (1 - (pad + (1 - 2 * pad) * nativeByte))
                assert(
                    math.abs(rendered - nativeY(values[sample])) < 1,
                    "Native padded/8-bit vertices remain within one logical pixel at UI scales 0.5–2"
                )
            end
        end
        assert(math.abs(nativeY(values[11]) - (first.y + last.y) / 2) < 0.000001)
    end
end
assert(layout.columns[6].width == 208 and layout.columns[6].left == 340)
local changed, color = Activity.comparison(activity, 6, "commits")
assert(changed == "↘ -100 vs Feb (full month)" and color == "error")
assert(Activity.comparison(activity, 2, "pulls") == "Lower bound · exact change unavailable")
assert(Activity.comparison(activity, 3, "repos") == "Not reported for this month")
assert(Activity.valueText(nil, false) == "—" and Activity.valueText(60, true) == "60+")
for i, month in ipairs(months) do
    print(month.date .. " " .. Activity.monthEnd(months, i))
end
print(
    "Tangled native layout: collisions, six columns, cubic sampling and exact label anchors passed"
)
