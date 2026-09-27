local fallback_domain = "hanasand.com"
local template_path = "/usr/local/openresty/nginx/errors/error.html"

local errors = {
    [400] = {"Bad Request", "The request could not be understood by this server."},
    [401] = {"Unauthorized", "This page requires authorization before it can be viewed."},
    [403] = {"Forbidden", "You do not have access to this page."},
    [404] = {"Page Not Found", "The page you are looking for does not exist on {{domain}}."},
    [405] = {"Method Not Allowed", "This request method is not allowed here."},
    [406] = {"Not Acceptable", "The requested response format is not available."},
    [408] = {"Request Timeout", "The server timed out waiting for the request."},
    [409] = {"Conflict", "The request conflicts with the current state of this resource."},
    [410] = {"Gone", "This resource is no longer available."},
    [418] = {"I'm a teapot", "This endpoint refuses to brew coffee."},
    [429] = {"Too Many Requests", "Slow down and try again in a moment."},
    [451] = {"Unavailable for Legal Reasons", "This resource is unavailable for legal reasons."},
    [500] = {"Internal Server Error", "The site could not be reached. Please try again."},
    [501] = {"Not Implemented", "This feature is not implemented on this server."},
    [502] = {"Bad Gateway", "Invalid response"},
    [503] = {"Service Unavailable", "The service is temporarily unavailable. Please try again soon."},
    [504] = {"Gateway Timeout", "The upstream service took too long to respond."},
}

local retryable = {
    [408] = true,
    [429] = true,
    [500] = true,
    [502] = true,
    [503] = true,
    [504] = true,
}

local function read_file(path)
    local file = io.open(path, "r")
    if not file then
        return nil
    end

    local body = file:read("*a")
    file:close()
    return body
end

local function html_escape(value)
    local escaped = tostring(value)
        :gsub("&", "&amp;")
        :gsub("<", "&lt;")
        :gsub(">", "&gt;")
        :gsub('"', "&quot;")
        :gsub("'", "&#39;")

    return escaped
end

local function js_escape(value)
    local escaped = html_escape(value)
        :gsub("\\", "\\\\")
        :gsub("'", "\\'")

    return escaped
end

local function base_domain(host)
    local clean_host = (host or fallback_domain):match("^[^:]+") or fallback_domain
    local labels = {}

    for label in clean_host:gmatch("[^.]+") do
        labels[#labels + 1] = label
    end

    if #labels >= 2 then
        return labels[#labels - 1] .. "." .. labels[#labels]
    end

    return clean_host
end

local code = tonumber(ngx.var.arg_code) or ngx.status or 500
local title, message = unpack(errors[code] or errors[500])
local domain = base_domain(ngx.var.host)
local is_hanasand = domain == "hanasand.com"
local body = read_file(template_path)

ngx.status = code
ngx.header.content_type = "text/html; charset=utf-8"
ngx.header["X-Request-ID"] = ngx.var.request_id or "unknown"

if not body then
    local is_light = false
    for cookie in (ngx.var.http_cookie or ""):gmatch("[^;]+") do
        if cookie:match("^%s*theme=light%s*$") then
            is_light = true
            break
        end
    end
    local canvas = is_light and "#f5f5f5" or "#070707"
    local panel = is_light and "#ffffff" or "#101010"
    local text = is_light and "#171a21" or "#f5f7fb"
    local muted = is_light and "#4d4d4d" or "#999999"
    ngx.say(string.format(
        "<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><meta name=\"color-scheme\" content=\"%s\"><title>%s</title><style>html,body{min-height:100%%}body{box-sizing:border-box;margin:0;padding:2rem;display:grid;place-items:center;background:%s;color:%s;font:16px system-ui,sans-serif}.card{max-width:36rem;padding:2rem;border:1px solid color-mix(in srgb,%s 14%%,transparent);border-radius:1rem;background:%s}p{color:%s;line-height:1.6}a{color:inherit}</style></head><body><main class=\"card\"><h1>%s</h1><p>%s</p><a href=\"https://%s\">Go home</a></main></body></html>",
        is_light and "light" or "dark",
        html_escape(tostring(code) .. " - " .. title),
        canvas,
        text,
        text,
        panel,
        muted,
        html_escape(tostring(code) .. " - " .. title),
        html_escape(message:gsub("{{domain}}", domain)),
        html_escape(domain)
    ))
    return
end

message = message:gsub("{{domain}}", domain)
body = body:gsub("{{code}}", tostring(code))
body = body:gsub("{{title}}", html_escape(title))
body = body:gsub("{{message}}", html_escape(message))
body = body:gsub("{{domain}}", html_escape(domain))
body = body:gsub("{{brand_class}}", is_hanasand and "hanasand-error" or "")
body = body:gsub("{{home_url}}", js_escape("https://" .. domain))
body = body:gsub("{{retryable}}", retryable[code] and "true" or "false")
body = body:gsub("{{request_id}}", html_escape(ngx.var.request_id or "unknown"))

ngx.say(body)
