local M = {}

local missing = {}

local function restore(targets, previous, logger, label)
    local restored = true
    for key, value in pairs(previous) do
        local ok, err
        if value == missing then
            targets:delete(key)
            ok = true
        else
            local forcible
            ok, err, forcible = targets:safe_set(key, value)
            if forcible then ok = false; err = err or "shared dictionary evicted a live entry" end
        end
        if not ok then
            restored = false
            logger(ngx.ERR, "Unable to restore last-good ", label, " route ", key, ": ", err or "unknown shared-dictionary error")
        end
    end
    return restored
end

-- Apply a route snapshot without evicting live entries. If a write fails,
-- attempt to restore keys touched by this refresh and skip stale-key cleanup.
-- Rollback can also fail, so callers must treat this as best-effort recovery.
function M.replace(targets, nextTargets, label, logger)
    local previous = {}
    for key, value in pairs(nextTargets) do
        local current = targets:get(key)
        if current ~= value then
            previous[key] = current == nil and missing or current
            local ok, err, forcible = targets:safe_set(key, value)
            if not ok or forcible then
                local reason = err or (forcible and "shared dictionary evicted a live entry" or "unknown shared-dictionary error")
                logger(ngx.WARN, "Unable to refresh ", label, " routes: ", reason,
                    "; attempted rollback and skipped stale-route cleanup. Routes may be partially updated if rollback fails")
                restore(targets, previous, logger, label)
                return false
            end
        end
    end

    for _, key in ipairs(targets:get_keys(0)) do
        if nextTargets[key] == nil then targets:delete(key) end
    end
    return true
end

function M.safeSet(targets, key, value, label, logger)
    local ok, err, forcible = targets:safe_set(key, value)
    if ok and not forcible then return true end
    logger(ngx.WARN, "Unable to refresh ", label, " route ", key, ": ", err or (forcible and "shared dictionary evicted a live entry" or "unknown shared-dictionary error"))
    return false
end

return M
