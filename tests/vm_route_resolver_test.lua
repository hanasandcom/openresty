local resolver = require "vm_route_resolver"
local fixtureFile = assert(io.open("tests/fixtures/vm-public-service-route.tsv", "r"))
local fixtureText = fixtureFile:read("*a")
fixtureFile:close()
local fixtureName, fixtureHostname, fixtureType, fixtureVmName, fixtureVmIp, fixturePortText = fixtureText:match("([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|(%d+)")
assert(fixtureName and fixtureHostname and fixtureType and fixtureVmName and fixtureVmIp and fixturePortText)

local values = {
    ["test3"] = "10.119.85.80",
    ["service:" .. fixtureType .. ":" .. fixtureHostname] = fixtureVmIp .. ":" .. fixturePortText,
    ["service:tls:api-vm.hanasand.com"] = "10.119.85.80:8443",
    ["service:minecraft-java:survival.hanasand.com"] = "10.119.85.80:25566",
}
local targets = { get = function(_, key) return values[key] end }

assert(resolver.resolve(fixtureHostname, 80, targets, fixtureType) == fixtureVmIp .. ":" .. fixturePortText)
assert(resolver.resolve(string.upper(fixtureHostname) .. ".", 80, targets, fixtureType) == fixtureVmIp .. ":" .. fixturePortText)
assert(resolver.resolve("api-vm.hanasand.com", 443, targets, "tls") == "10.119.85.80:8443")
assert(resolver.resolve("survival.hanasand.com", 25565, targets, "minecraft-java") == "10.119.85.80:25566")
assert(resolver.resolve(fixtureHostname, 443, targets, "tls") == nil)
assert(resolver.resolve(fixtureHostname, 80, targets, "minecraft-java") == nil)
assert(resolver.resolve("8080-test3.hanasand.com", 443, targets) == "10.119.85.80:8080")
assert(resolver.resolve("test3.hanasand.com", 443, targets) == "10.119.85.80:443")
assert(resolver.resolve("test3.hanasand.com", 25565, targets, "minecraft-java") == "10.119.85.80:25565")

assert(resolver.serviceKey("a.hanasand.com", "http") == "service:http:a.hanasand.com")
assert(resolver.serviceKey("a-.hanasand.com", "http") == nil)
assert(resolver.serviceKey("a.hanasand.com", "udp") == nil)
assert(resolver.validServiceName("a"))
assert(not resolver.validServiceName("a-"))
assert(resolver.validPort(443))
assert(not resolver.validPort(65536))
assert(not resolver.validIp("256.119.85.80"))

print("VM public-service route contract passed")
