local M = {}

local function validIp(ip)
    if type(ip) ~= "string" then return false end
    local a, b, c, d = ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if not a then return false end
    for _, part in ipairs({ a, b, c, d }) do
        local value = tonumber(part)
        if not value or value < 0 or value > 255 then return false end
    end
    return true
end

function M.resolve(hostname, defaultPort, targets)
    if type(hostname) ~= "string" then return nil end
    local host = hostname:lower():gsub("%.$", "")
    local portText, vmName = host:match("^(%d+)%-([a-z0-9][a-z0-9%-]*)%.hanasand%.com$")
    if not vmName then vmName = host:match("^([a-z0-9][a-z0-9%-]*)%.hanasand%.com$") end
    if not vmName then return nil end

    local port = portText and tonumber(portText) or tonumber(defaultPort)
    if not port or port < 1 or port > 65535 or port % 1 ~= 0 then return nil end
    local ip = targets:get(vmName)
    if not validIp(ip) then return nil end
    return ip .. ":" .. port, vmName, port
end

function M.isVmHostname(hostname)
    if type(hostname) ~= "string" then return false end
    local host = hostname:lower():gsub("%.$", "")
    return host:match("^[a-z0-9][a-z0-9%-]*%.hanasand%.com$") ~= nil
        or host:match("^%d+%-[a-z0-9][a-z0-9%-]*%.hanasand%.com$") ~= nil
end

return M
