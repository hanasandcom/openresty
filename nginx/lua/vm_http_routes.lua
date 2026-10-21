local http = require "resty.http"
local json = require "cjson.safe"
local targets = ngx.shared.vm_http_routes
local apiUrl = os.getenv("VM_PORT_ROUTES_API_URL") or "http://127.0.0.1:8080/api/vms/internal/public-ports"
local syncToken = os.getenv("VM_PORT_ROUTE_TOKEN") or ""

local function validIp(ip)
    if type(ip) ~= "string" then return false end
    local a, b, c, d = ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    return a and tonumber(a) <= 255 and tonumber(b) <= 255 and tonumber(c) <= 255 and tonumber(d) <= 255
end

local function refresh(premature)
    if premature then return end
    local client = http.new()
    client:set_timeout(2500)
    local response, err = client:request_uri(apiUrl, { method = "GET", headers = { Authorization = "Bearer " .. syncToken } })
    if not response or response.status ~= 200 then
        ngx.log(ngx.WARN, "VM website route refresh failed: ", err or (response and response.status))
        return
    end

    local routes = json.decode(response.body)
    if type(routes) ~= "table" then
        ngx.log(ngx.WARN, "VM website route refresh returned invalid JSON")
        return
    end

    local nextTargets = {}
    for _, route in ipairs(routes) do
        local hostname = type(route.hostname) == "string" and route.hostname:lower() or ""
        local port = tonumber(route.port)
        if route.type == "http" and hostname:match("^port%-[a-z0-9%-]+%.hanasand%.com$")
            and validIp(route.vmIp) and port and port >= 1 and port <= 65535 then
            nextTargets[hostname] = "http://" .. route.vmIp .. ":" .. math.floor(port)
        end
    end

    targets:flush_all()
    for hostname, backend in pairs(nextTargets) do targets:set(hostname, backend) end
end

if ngx.worker.id() == 0 then
    local ok, err = ngx.timer.every(5, refresh)
    if not ok then ngx.log(ngx.ERR, "Unable to start VM website route sync: ", err) end
end
