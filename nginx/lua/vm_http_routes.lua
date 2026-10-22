local http = require "resty.http"
local json = require "cjson.safe"
local targets = ngx.shared.vm_http_routes
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
    for _, route in ipairs(routes) do
        local vmName = type(route.vmName) == "string" and route.vmName:lower() or ""
        local hostname = type(route.hostname) == "string" and route.hostname:lower() or ""
        local ip = type(route.vmIp) == "string" and route.vmIp or ""
        if vmName:match("^[a-z0-9][a-z0-9%-]*$") and hostname == vmName .. ".hanasand.com"
            and require("vm_route_resolver").resolve(hostname, 80, { get = function(_, key) return key == vmName and ip or nil end }) then
            nextTargets[vmName] = ip
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
