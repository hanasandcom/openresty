local routeSync = require "vm_port_routes"

local function readSocketVarInt(sock, position)
    local value = 0
    for index = 0, 4 do
        local data, err = sock:peek(position + index)
        if not data then return nil, nil, err end
        local byte = string.byte(data, position + index)
        if not byte then return nil, nil, "incomplete VarInt" end
        value = value + (byte % 128) * (2 ^ (7 * index))
        if byte < 128 then return value, position + index + 1 end
    end
    return nil, nil, "VarInt exceeds five bytes"
end

local function readStringVarInt(data, position)
    local value = 0
    for index = 0, 4 do
        local byte = string.byte(data, position + index)
        if not byte then return nil, nil end
        value = value + (byte % 128) * (2 ^ (7 * index))
        if byte < 128 then return value, position + index + 1 end
    end
    return nil, nil
end

local function readMinecraftHostname()
    local sock, socketErr = ngx.req.socket()
    if not sock then return nil, socketErr end
    local packetLength, afterLength, lengthErr = readSocketVarInt(sock, 1)
    if not packetLength then return nil, lengthErr end
    if packetLength < 1 or packetLength > 4096 then return nil, "invalid handshake length" end
    local packet, packetErr = sock:peek(afterLength - 1 + packetLength)
    if not packet then return nil, packetErr end

    local packetId, position = readStringVarInt(packet, afterLength)
    if packetId ~= 0 then return nil, "not a Minecraft handshake" end
    local _, afterProtocol = readStringVarInt(packet, position)
    if not afterProtocol then return nil, "invalid protocol version" end
    local hostnameLength, afterHostnameLength = readStringVarInt(packet, afterProtocol)
    if not hostnameLength or hostnameLength < 1 or hostnameLength > 255 then return nil, "invalid handshake hostname length" end
    local hostname = packet:sub(afterHostnameLength, afterHostnameLength + hostnameLength - 1)
    if #hostname ~= hostnameLength then return nil, "incomplete handshake hostname" end
    return hostname:lower()
end

local M = {}
function M.registerHandshakeRoute()
    local hostname, err = readMinecraftHostname()
    if not hostname then return nil, err end
    local backend = routeSync.resolve(hostname, 25565)
    if not backend then return false end
    local ok, routeErr = routeSync.updateMcRoute(hostname, backend)
    if not ok then return nil, routeErr end
    return true
end

return M
