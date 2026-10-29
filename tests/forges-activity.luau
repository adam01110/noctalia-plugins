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
local svg = Activity.svg(activity, {
    background = "#202124",
    current = "#303134",
    text = "#e8eaed",
    border = "#777777",
    rising = "#a8c7fa",
    falling = "#f28b82",
}, "github")
assert(svg:find('stroke-dasharray="3 3"', 1, true))
assert(svg:find("—", 1, true), "Unknown metrics must be visibly unavailable")
local layout = Activity.layout({ months = Activity.months() })
for i = 1, 6 do
    local ys = {}
    for _, metric in ipairs(Activity.metrics) do
        table.insert(ys, layout.points[metric][i].y)
    end
    table.sort(ys)
    for j = 2, #ys do
        assert(ys[j] - ys[j - 1] >= 28)
    end
end
print(svg)
