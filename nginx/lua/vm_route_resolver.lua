local M = {}
local reservedServiceNames = {
    api = true, ["api-browsers"] = true, browsers = true, cashflow = true, cdn = true,
    git = true, hanasand = true, idk = true, ["idk-api"] = true, identity = true,
    internal = true, logs = true, mail = true, ["name-pending"] = true, np = true,
    status = true, support = true, turn = true, www = true, ["67"] = true,
}

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

local function validBackend(backend)
    if type(backend) ~= "string" then return false end
    local ip, portText = backend:match("^(%d+%.%d+%.%d+%.%d+):(%d+)$")
    local port = tonumber(portText)
    return validIp(ip) and port ~= nil and port >= 1 and port <= 65535 and port % 1 == 0
end

function M.validIp(ip) return validIp(ip) end
function M.validPort(port)
    local value = tonumber(port)
    return value ~= nil and value >= 1 and value <= 65535 and value % 1 == 0
end

function M.validServiceName(name)
    return type(name) == "string" and #name >= 1 and #name <= 40
        and name:match("^[a-z0-9][a-z0-9%-]*$") ~= nil
        and name:match("[a-z0-9]$") ~= nil
        and not reservedServiceNames[name]
        and not name:match("^%d+%-[a-z0-9%-]+$")
end

function M.serviceKey(hostname, routeType)
    if type(hostname) ~= "string" then return nil end
    local host = hostname:lower():gsub("%.$", "")
    local serviceName = host:match("^([a-z0-9][a-z0-9%-]*)%.hanasand%.com$")
    if not M.validServiceName(serviceName) then return nil end
    if routeType ~= "http" and routeType ~= "tls" and routeType ~= "minecraft-java" then return nil end
    return "service:" .. routeType .. ":" .. host
end

function M.resolveService(hostname, routeType, targets)
    local key = M.serviceKey(hostname, routeType)
    if not key then return nil end
    local backend = targets:get(key)
    if not validBackend(backend) then return nil end
    return backend
end

function M.resolve(hostname, defaultPort, targets, routeType)
    if type(hostname) ~= "string" then return nil end
    local host = hostname:lower():gsub("%.$", "")
    if routeType then
        local serviceBackend = M.resolveService(host, routeType, targets)
        if serviceBackend then return serviceBackend end
    end
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
