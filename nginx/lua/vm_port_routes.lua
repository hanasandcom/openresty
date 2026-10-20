local http = require "resty.http"
local json = require "cjson.safe"
local targets = ngx.shared.vm_route_targets
local apiUrl = os.getenv("VM_PORT_ROUTES_API_URL") or "http://127.0.0.1:8080/api/vms/internal/public-ports"
local syncToken = os.getenv("VM_PORT_ROUTE_TOKEN") or ""
local routePath = os.getenv("VM_MINECRAFT_ROUTES_PATH") or "/var/run/vm-routes/minecraft.json"
local seedFile = io.open("/usr/local/openresty/nginx/conf/minecraft-routes-seed.json", "r")
local seed = seedFile and json.decode(seedFile:read("*a")) or nil
if seedFile then seedFile:close() end
local staticMinecraft = seed and seed.mappings or {}

local function validIp(ip)
    if type(ip) ~= "string" then return false end
    local a, b, c, d = ip:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    return a and tonumber(a) <= 255 and tonumber(b) <= 255 and tonumber(c) <= 255 and tonumber(d) <= 255
end

local function writeMinecraftRoutes(mappings)
    local payload = assert(json.encode({ mappings = mappings }))
    local tempPath = routePath .. ".tmp"
    local file = io.open(tempPath, "w")
    if not file then return nil, "unable to open route file" end
    file:write(payload)
    file:close()
    local ok, err = os.rename(tempPath, routePath)
    if not ok then os.remove(tempPath); return nil, err end
    return true
end

local function refresh(premature)
    if premature then return end
    local client = http.new()
    client:set_timeout(2500)
    local response, err = client:request_uri(apiUrl, { method = "GET", headers = { Authorization = "Bearer " .. syncToken } })
    if not response or response.status ~= 200 then
        ngx.log(ngx.WARN, "VM public route refresh failed: ", err or (response and response.status))
        return
    end

    local routes = json.decode(response.body)
    if type(routes) ~= "table" then
        ngx.log(ngx.WARN, "VM public route refresh returned invalid JSON")
        return
    end
    local nextMinecraft = {}
    for name, backend in pairs(staticMinecraft) do nextMinecraft[name] = backend end
    local nextTargets = {}
    for _, route in ipairs(routes) do
        local hostname = type(route.hostname) == "string" and route.hostname:lower() or ""
        local port = tonumber(route.port)
        if hostname:match("^port%-[a-z0-9%-]+%.hanasand%.com$") and validIp(route.vmIp) and port and port >= 1 and port <= 65535 then
            local backend = route.vmIp .. ":" .. math.floor(port)
            if route.type == "tls" then nextTargets[hostname] = backend end
            if route.type == "minecraft-java" then nextMinecraft[hostname] = backend end
        end
    end
    targets:flush_all()
    for hostname, backend in pairs(nextTargets) do targets:set(hostname, backend) end
    local ok, writeErr = writeMinecraftRoutes(nextMinecraft)
    if not ok then ngx.log(ngx.ERR, "Unable to update Minecraft routes: ", writeErr) end
end

if ngx.worker.id() == 0 then
    local ok, err = ngx.timer.every(5, refresh)
    if not ok then ngx.log(ngx.ERR, "Unable to start VM public route sync: ", err) end
end
