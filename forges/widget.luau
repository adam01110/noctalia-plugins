--!nonstrict
local function render()
    local snapshot = noctalia.state.get("forges.snapshot") or {}
    local forge = snapshot.provider == "github" and "GitHub"
        or (snapshot.provider == "gitlab" and "GitLab" or "Tangled")
    barWidget.setGlyph(snapshot.provider == "github" and "brand-github" or "git-branch")
    barWidget.setText("")
    local status = snapshot.status == "ready" and "" or (" · " .. (snapshot.status or "loading"))
    barWidget.setTooltip(
        "Forges · "
            .. forge
            .. ((snapshot.account or "") ~= "" and (" · @" .. snapshot.account) or "")
            .. status
    )
end
noctalia.state.watch("forges.snapshot", render)
function onClick()
    noctalia.togglePanel("adam0/forges:panel")
end
function onRightClick()
    noctalia.state.set("forges.command", { op = "refresh", nonce = noctalia.nowMs() })
end
render()
