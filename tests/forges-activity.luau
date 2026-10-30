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
assert(months[1].date == "2023-04" and months[1].label == "Apr")
assert(months[11].date == "2024-02" and months[11].label == "Feb")
assert(Activity.monthEnd(months, 11) == "2024-02-29T23:59:59Z")
assert(Activity.monthEnd(months, 10) == "2024-01-31T23:59:59Z")
assert(Activity.monthEnd(months, 12) == "2024-03-01T00:00:00Z")
assert(
    Activity.monthEnd({ { date = "2100-02" }, { date = "2100-03" } }, 1) == "2100-02-28T23:59:59Z"
)
assert(
    Activity.monthEnd({ { date = "2000-02" }, { date = "2000-03" } }, 1) == "2000-02-29T23:59:59Z"
)
for i, month in ipairs(months) do
    month.values = { commits = 1300 - i * 100, pulls = i * 10, repos = i % 3, issues = 5 }
end
months[2].lowerBounds.pulls = true
months[3].values.repos = nil
local activity = { months = months }
local empty = Activity.fromCalendar({ activity = { months = {} } })
assert(#empty.months == 12 and empty.months[1].date == "2023-04")
for _, month in ipairs(empty.months) do
    for _, metric in ipairs(Activity.metrics) do
        assert(month.values[metric] == 0)
    end
end
local sparse = Activity.fromCalendar({ activity = activity })
assert(sparse.months[3].values.repos == 0 and months[3].values.repos == nil)
assert(sparse.months[2].lowerBounds.pulls, "Zero filling must preserve API lower bounds")
local layout = Activity.layout(activity)
assert(layout.width == 548 and layout.height == 210 and #layout.metrics == 4)
for i = 1, 12 do
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
    for i = 1, 11 do
        local first, last = layout.points[metric][i], layout.points[metric][i + 1]
        local frame = Activity.curveFrame(first, last, layout.height)
        local values = Activity.curveValues(first, last, frame.height, frame.top, frame.pad)
        assert(#values == 67)
        for _, value in ipairs(values) do
            assert(value >= 0 and value <= 1)
        end
        local function nativeY(value)
            return frame.top + frame.height * (1 - frame.pad - (1 - 2 * frame.pad) * value)
        end
        -- Shader index = 2 + scroll(1) + x * (count-3), followed by lead extrapolation.
        local firstVisible = values[4]
        local lead = math.clamp(values[67] + (values[67] - values[66]) * 0.5, 0, 1)
        assert(math.abs(nativeY(firstVisible) - first.y) < 0.000001)
        assert(math.abs(nativeY(lead) - last.y) < 0.000001)
        assert(
            math.abs(nativeY(values[36]) - (first.y + last.y) / 2) < 0.000001,
            "The shader midpoint must not lag or lead the actual cubic"
        )
        for _, sample in ipairs({ firstVisible, lead }) do
            local nativeByte = math.floor(sample * 255) / 255
            assert(math.abs(nativeY(nativeByte) - nativeY(sample)) < 0.75)
        end
        -- Exercise native 8-bit upload + Hermite interpolation, not just our input samples.
        local pixels = {}
        for _, value in ipairs(values) do
            table.insert(pixels, math.floor(value * 255) / 255)
        end
        table.insert(pixels, pixels[#pixels]) -- the pinned extrapolated lead
        local function fetch(index)
            return pixels[math.clamp(index + 1, 1, #pixels)]
        end
        for sample = 0, 128 do
            local x = sample / 128
            local position = 3 + x * (#values - 3)
            local index, t = math.floor(position), position % 1
            local y0, y1, y2, y3 =
                fetch(index - 1), fetch(index), fetch(index + 1), fetch(index + 2)
            local m1, m2 = (y2 - y0) * 0.25, (y3 - y1) * 0.25
            local y = (2 * t ^ 3 - 3 * t ^ 2 + 1) * y1
                + (t ^ 3 - 2 * t ^ 2 + t) * m1
                + (-2 * t ^ 3 + 3 * t ^ 2) * y2
                + (t ^ 3 - t ^ 2) * m2
            local u = x
            for _ = 1, 5 do
                u -= (1.5 * u - 1.5 * u * u + u * u * u - x) / (1.5 - 3 * u + 3 * u * u)
            end
            local exact = first.y + (last.y - first.y) * (3 * u * u - 2 * u * u * u)
            assert(
                math.abs(nativeY(y) - exact) < 0.9,
                "Rendered native cubic stays subpixel-aligned"
            )
        end
        assert(frame.height <= layout.height and frame.top >= 0)
        if math.abs(last.y - first.y) < 96 then
            assert(frame.height == 128, "Gentle curves use a finer vertical quantization range")
        end
    end
end
assert(layout.columns[12].width == 152 and layout.columns[12].left == 396)
local changed, color = Activity.comparison(activity, 12, "commits")
assert(changed == "↘ -100 vs Feb (full month)" and color == "error")
assert(Activity.comparison(activity, 2, "pulls") == "Lower bound · exact change unavailable")
assert(Activity.comparison(activity, 3, "repos") == "Not reported for this month")
assert(Activity.valueText(nil, false) == "—" and Activity.valueText(60, true) == "60+")
for i, month in ipairs(months) do
    print(month.date .. " " .. Activity.monthEnd(months, i))
end
print(
    "Tangled native layout: collisions, twelve columns, cubic sampling and exact label anchors passed"
)
