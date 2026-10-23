local http = require "resty.http"
local json = require "cjson.safe"
local targets = ngx.shared.vm_route_targets
local mcTargets = ngx.shared.vm_mc_route_targets
local apiUrl = os.getenv("VM_PORT_ROUTES_API_URL") or "http://127.0.0.1:8080/api/vms/internal/public-ports"
local syncToken = os.getenv("VM_PORT_ROUTE_TOKEN") or ""
local mcApiUrl = os.getenv("VM_MINECRAFT_ROUTER_API_URL") or "http://127.0.0.1:25567"
local resolver = require "vm_route_resolver"

local staticFile = io.open("/usr/local/openresty/nginx/conf/minecraft-routes-seed.json", "r")
local staticRoutes = staticFile and json.decode(staticFile:read("*a")) or nil
if staticFile then staticFile:close() end
local staticMinecraft = staticRoutes and staticRoutes.mappings or {}

local function request(uri, method, body)
    local client = http.new()
    client:set_timeout(1500)
    local response, err = client:request_uri(mcApiUrl .. uri, {
        method = method,
        body = body,
        headers = body and { ["Content-Type"] = "application/json" } or nil,
    })
    if not response then return nil, err end
    return response
end

local function updateMcRoute(hostname, backend, currentBackend)
    if not currentBackend then
        local existing, getErr = request("/routes", "GET")
        if not existing or existing.status ~= 200 then return nil, getErr or (existing and existing.status) end
        local routes = json.decode(existing.body)
        local route = type(routes) == "table" and routes[hostname] or nil
        currentBackend = type(route) == "table" and route.backend or nil
    end
    if currentBackend == backend then
        mcTargets:set(hostname, backend)
        return true
    end
    if currentBackend then
        local deleted, deleteErr = request("/routes/" .. ngx.escape_uri(hostname), "DELETE")
        if not deleted or (deleted.status ~= 200 and deleted.status ~= 204 and deleted.status ~= 404) then
            return nil, deleteErr or (deleted and deleted.status)
        end
    end
    local response, err = request("/routes", "POST", json.encode({ serverAddress = hostname, backend = backend }))
    if not response or response.status < 200 or response.status >= 300 then
        return nil, err or (response and response.status)
    end
    mcTargets:set(hostname, backend)
    return true
end

local function removeMcRoute(hostname)
    local response, err = request("/routes/" .. ngx.escape_uri(hostname), "DELETE")
    if not response or (response.status ~= 200 and response.status ~= 204 and response.status ~= 404) then
        ngx.log(ngx.WARN, "Unable to remove stale VM Minecraft route ", hostname, ": ", err or (response and response.status))
        return
    end
    mcTargets:delete(hostname)
end

local function reconcileMcRoutes()
    local response, err = request("/routes", "GET")
    if not response or response.status ~= 200 then
        ngx.log(ngx.WARN, "Unable to inspect Minecraft routes for VM cleanup: ", err or (response and response.status))
        return
    end
    local routes = json.decode(response.body)
    if type(routes) ~= "table" then
        ngx.log(ngx.WARN, "Minecraft router returned invalid route data")
        return
    end
    for hostname, route in pairs(routes) do
        local host = type(hostname) == "string" and hostname:lower() or ""
        if resolver.isVmHostname(host) and not staticMinecraft[host] then
            local expected = resolver.resolve(host, 25565, targets, "minecraft-java")
            local backend = type(route) == "table" and route.backend or nil
            if not expected then
                removeMcRoute(host)
            elseif backend ~= expected then
                local ok, updateErr = updateMcRoute(host, expected, backend)
                if not ok then ngx.log(ngx.WARN, "Unable to refresh VM Minecraft route ", host, ": ", updateErr) end
            else
                mcTargets:set(host, expected)
            end
        end
    end
end

local function refresh(premature)
    if premature then return end
    local client = http.new()
    client:set_timeout(2500)
    local response, err = client:request_uri(apiUrl, {
        method = "GET",
        headers = { Authorization = "Bearer " .. syncToken },
    })
    if not response or response.status ~= 200 then
        ngx.log(ngx.WARN, "VM route refresh failed: ", err or (response and response.status))
        return
    end

    local routes = json.decode(response.body)
    if type(routes) ~= "table" then
        ngx.log(ngx.WARN, "VM route refresh returned invalid JSON")
        return
    end

    local nextTargets = {}
    local vmNames = {}
    for _, route in ipairs(routes) do
        local vmName = type(route.vmName) == "string" and route.vmName:lower() or ""
        local hostname = type(route.hostname) == "string" and route.hostname:lower() or ""
        if not route.type and vmName:match("^[a-z0-9][a-z0-9%-]*$") and hostname == vmName .. ".hanasand.com" then
            vmNames[vmName] = true
        end
    end
    for _, route in ipairs(routes) do
        if type(route) ~= "table" then
            ngx.log(ngx.WARN, "VM route refresh contained a non-object route; retaining last good map")
            return
        end
        local vmName = type(route.vmName) == "string" and route.vmName:lower() or ""
        local hostname = type(route.hostname) == "string" and route.hostname:lower() or ""
        local ip = type(route.vmIp) == "string" and route.vmIp or ""
        if not route.type then
            if not vmName:match("^[a-z0-9][a-z0-9%-]*$") or hostname ~= vmName .. ".hanasand.com" or not resolver.validIp(ip) then
                ngx.log(ngx.WARN, "VM route refresh contained an invalid VM route; retaining last good map")
                return
            end
            nextTargets[vmName] = ip
        elseif route.type == "tls" or route.type == "minecraft-java" or route.type == "http" then
            local serviceName = type(route.name) == "string" and route.name:lower() or ""
            local key = resolver.serviceKey(hostname, route.type)
            local port = tonumber(route.port)
            if not key or hostname ~= serviceName .. ".hanasand.com" or vmNames[serviceName]
                or not resolver.validServiceName(serviceName) or not vmName:match("^[a-z0-9][a-z0-9%-]*$")
                or not resolver.validIp(ip) or not resolver.validPort(port) or route.hostname ~= hostname then
                ngx.log(ngx.WARN, "VM route refresh contained an invalid service route; retaining last good map")
                return
            end
            nextTargets[key] = ip .. ":" .. math.floor(port)
        else
            ngx.log(ngx.WARN, "VM route refresh contained an unknown route type; retaining last good map")
            return
        end
    end

    for vmName, ip in pairs(nextTargets) do targets:set(vmName, ip) end
    for _, vmName in ipairs(targets:get_keys(0)) do
        if not nextTargets[vmName] then targets:delete(vmName) end
    end
    reconcileMcRoutes()
end

if ngx.worker.id() == 0 then
    local started, startErr = ngx.timer.at(0, refresh)
    if not started then ngx.log(ngx.ERR, "Unable to start initial VM route sync: ", startErr) end
    local ok, err = ngx.timer.every(5, refresh)
    if not ok then ngx.log(ngx.ERR, "Unable to start VM route sync: ", err) end
end

return {
    resolve = function(hostname, defaultPort, routeType)
        return resolver.resolve(hostname, defaultPort, targets, routeType)
    end,
    updateMcRoute = updateMcRoute,
}
