--!nonstrict

local command = noctalia.getConfig("command") or "performance-mode"
local enabled = false
local busy = false
local enabledGlyph = noctalia.getConfig("enabled_glyph")
local disabledGlyph = noctalia.getConfig("disabled_glyph")
local enabledTooltip = noctalia.getConfig("enabled_tooltip")
local disabledTooltip = noctalia.getConfig("disabled_tooltip")

local function render()
    barWidget.setGlyph(if enabled then enabledGlyph else disabledGlyph)
    barWidget.setTooltip(if enabled then enabledTooltip else disabledTooltip)
end

local function refresh(showNotification)
    busy = true
    local accepted = noctalia.runAsync(command .. " status", function(result)
        enabled = result.exitCode == 0
        busy = false
        render()
        if showNotification then
            noctalia.notify("Performance mode", if enabled then "Enabled" else "Disabled")
        end
    end)

    if not accepted then
        busy = false
        noctalia.notifyError("Performance mode", "Could not read performance mode status")
        render()
    end
end

local function toggle()
    if busy then return end
    busy = true

    local accepted = noctalia.runAsync(command .. " toggle", function(result)
        if result.exitCode ~= 0 then
            busy = false
            noctalia.notifyError("Performance mode", "Could not toggle performance mode")
            render()
            return
        end
        refresh(true)
    end)

    if not accepted then
        busy = false
        noctalia.notifyError("Performance mode", "Could not start performance mode command")
        render()
    end
end

function onClick()
    toggle()
end

function onRightClick()
    refresh(true)
end

function onIpc(event, _payload)
    if event == "toggle" then
        toggle()
    elseif event == "refresh" then
        refresh(true)
    end
end

render()
refresh(false)
