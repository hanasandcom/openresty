local http = require "resty.http"
local json = require "cjson.safe"
local targets = ngx.shared.vm_http_routes
local resolver = require "vm_route_resolver"
local apiUrl = os.getenv("VM_PORT_ROUTES_API_URL") or "http://127.0.0.1:8080/api/vms/internal/public-ports"
local syncToken = os.getenv("VM_PORT_ROUTE_TOKEN") or ""

local function refresh(premature)
    if premature then return end
    local client = http.new()
    client:set_timeout(2500)
    local response, err = client:request_uri(apiUrl, { method = "GET", headers = { Authorization = "Bearer " .. syncToken } })
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
            ngx.log(ngx.WARN, "VM route refresh contained a non-object route; retaining last good HTTP map")
            return
        end
        local vmName = type(route.vmName) == "string" and route.vmName:lower() or ""
        local hostname = type(route.hostname) == "string" and route.hostname:lower() or ""
        local ip = type(route.vmIp) == "string" and route.vmIp or ""
        if not route.type then
            if not vmName:match("^[a-z0-9][a-z0-9%-]*$") or hostname ~= vmName .. ".hanasand.com" or not resolver.validIp(ip) then
                ngx.log(ngx.WARN, "VM route refresh contained an invalid VM route; retaining last good HTTP map")
                return
            end
            nextTargets[vmName] = ip
        elseif route.type == "http" or route.type == "tls" or route.type == "minecraft-java" then
            local serviceName = type(route.name) == "string" and route.name:lower() or ""
            local key = resolver.serviceKey(hostname, route.type)
            local port = tonumber(route.port)
            if not key or hostname ~= serviceName .. ".hanasand.com" or vmNames[serviceName]
                or not resolver.validServiceName(serviceName) or not vmName:match("^[a-z0-9][a-z0-9%-]*$")
                or not resolver.validIp(ip) or not resolver.validPort(port) then
                ngx.log(ngx.WARN, "VM route refresh contained an invalid service route; retaining last good HTTP map")
                return
            end
            if route.type == "http" then
                local backend = ip .. ":" .. math.floor(port)
                nextTargets[key] = backend
                nextTargets[hostname] = "http://" .. backend
            end
        else
            ngx.log(ngx.WARN, "VM route refresh contained an unknown route type; retaining last good HTTP map")
            return
        end
    end

    for vmName, ip in pairs(nextTargets) do targets:set(vmName, ip) end
    for _, vmName in ipairs(targets:get_keys(0)) do
        if not nextTargets[vmName] then targets:delete(vmName) end
    end
end

if ngx.worker.id() == 0 then
    local started, startErr = ngx.timer.at(0, refresh)
    if not started then ngx.log(ngx.ERR, "Unable to start initial VM route sync: ", startErr) end
    local ok, err = ngx.timer.every(5, refresh)
    if not ok then ngx.log(ngx.ERR, "Unable to start VM route sync: ", err) end
end
