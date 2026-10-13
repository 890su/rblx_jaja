--!strict
local Shared = game:GetService("ReplicatedStorage").Shared
local Zone = require(Shared.Util.BiomeZone)
local Zones = require(Shared.Config.Zones)
local passed = 0
local function check(actual: number, expected: number)
	assert(actual == expected, `biome boundary: {actual} != {expected}`)
	passed += 1
end
check(Zone.at(10), 0)
check(Zone.at(0), 1)
check(Zone.at(-1, 0), 0)
check(Zone.at(-10, 0), 1)
check(Zone.at(1, 1), 1)
check(Zone.at(10, 1), 0)
local z = 0
for index, spec in Zones.ZONES do
	check(Zone.at(z - spec.lengthStuds / 2), index)
	z -= spec.lengthStuds
	if index < #Zones.ZONES then
		check(Zone.at(z), index + 1)
		check(Zone.at(z - 1, index), index)
		check(Zone.at(z - 10, index), index + 1)
		check(Zone.at(z + 1, index + 1), index + 1)
		check(Zone.at(z + 10, index + 1), index)
	end
end
check(Zone.at(-5000), #Zones.ZONES)
check(Zone.at(-2000, 1), 3) -- teleport skips boundaries immediately
check(Zone.at(40, 5), 0) -- respawn returns to the station
return `PASS {passed}`
