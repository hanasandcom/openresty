_G.ngx = { WARN = "warn", ERR = "error" }

local store = require "vm_route_store"

local function newDict(initial, failAt)
    local values = initial or {}
    local calls = 0
    local keysCalls = 0
    local dict = {
        values = values,
        get = function(_, key) return values[key] end,
        safe_set = function(_, key, value)
            calls = calls + 1
            if (type(failAt) == "table" and failAt[calls]) or calls == failAt then
                return nil, "no memory", false
            end
            values[key] = value
            return true, nil, false
        end,
        delete = function(_, key) values[key] = nil end,
        get_keys = function()
            keysCalls = keysCalls + 1
            local keys = {}
            for key in pairs(values) do table.insert(keys, key) end
            return keys
        end,
        set = function() error("route synchronization must not use evicting set()") end,
    }
    return dict, function() return calls, keysCalls end
end

do
    local dict, counts = newDict({ a = "old-a", b = "old-b", stale = "old-stale" }, 2)
    local logs = {}
    local ok = store.replace(dict, { a = "new-a", b = "new-b", fresh = "new" }, "stream", function(level, ...)
        table.insert(logs, { level, ... })
    end)
    local writes, cleanupCalls = counts()
    assert(not ok, "failed route writes should abort the snapshot")
    assert(dict.values.a == "old-a" and dict.values.b == "old-b", "failed snapshot should restore last-good values")
    assert(dict.values.stale == "old-stale" and dict.values.fresh == nil, "failed snapshot must not clean stale routes or retain new partial routes")
    assert(cleanupCalls == 0, "failed snapshot must not enumerate routes for cleanup")
    assert(writes >= 3 and writes <= 4, "writes before and during rollback should be bounded")
    assert(#logs == 1 and logs[1][1] == ngx.WARN, "shared-dictionary failure should be logged")
end

do
    local dict, counts = newDict({ a = "old-a", b = "old-b", stale = "old-stale" }, { [2] = true, [3] = true, [4] = true })
    local logs = {}
    local ok = store.replace(dict, { a = "new-a", b = "new-b" }, "HTTP", function(level, ...)
        table.insert(logs, { level, table.concat({ ... }) })
    end)
    local writes, cleanupCalls = counts()
    assert(not ok, "failed rollback must still abort the snapshot")
    assert((dict.values.a == "new-a" and dict.values.b == "old-b")
        or (dict.values.b == "new-b" and dict.values.a == "old-a"),
        "failed rollback should leave the changed route observable in this mock")
    assert(dict.values.stale == "old-stale", "failed snapshot must skip stale-route cleanup")
    assert(cleanupCalls == 0, "failed rollback must not enumerate routes for cleanup")
    assert(writes == 4, "test should exercise one failed snapshot write and failures restoring both touched keys")
    assert(#logs == 3 and logs[1][1] == ngx.WARN and logs[2][1] == ngx.ERR and logs[3][1] == ngx.ERR,
        "snapshot failure and both rollback failures should be logged")
    assert(logs[1][2]:find("skipped stale%-route cleanup") and logs[1][2]:find("may be partially updated"),
        "snapshot failure log should explain skipped cleanup and best-effort rollback")
    assert(logs[2][2]:find("Unable to restore last%-good HTTP route")
        and logs[3][2]:find("Unable to restore last%-good HTTP route"), "failed restorations should identify their routes")
end

do
    local dict, counts = newDict({ stale = "old", mapped = "old" })
    local ok = store.replace(dict, { mapped = "new", fresh = "target" }, "HTTP", function() end)
    local _, cleanupCalls = counts()
    assert(ok, "complete route snapshot should succeed")
    assert(dict.values.mapped == "new" and dict.values.fresh == "target", "new route values should be stored")
    assert(dict.values.stale == nil and cleanupCalls == 1, "stale routes should be removed only after successful writes")
end

do
    local dict = {
        safe_set = function() return nil, "no memory", false end,
        set = function() error("Minecraft cache must not use evicting set()") end,
    }
    local logs = 0
    local ok = store.safeSet(dict, "survival.hanasand.com", "10.0.0.2:25565", "Minecraft cache", function(level)
        assert(level == ngx.WARN)
        logs = logs + 1
    end)
    assert(not ok and logs == 1, "Minecraft cache allocation failures should be logged")
end

print("VM route store reliability contract passed")
