-- Adapted from Shangshui0302's GitHub Kanban (MIT).
local Data = {}
function Data.profile(raw)
    if type(raw.login) ~= "string" or raw.login == "" then
        return nil
    end
    return { login = raw.login, name = raw.name or raw.login }
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
        if i > 30 then
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
return Data
