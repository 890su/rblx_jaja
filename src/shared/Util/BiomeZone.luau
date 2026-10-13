--!strict
local Zones = require(script.Parent.Parent.Config.Zones)
local Config = require(script.Parent.Parent.Config.BiomeAtmosphere)
local boundaries = { 0 }
for i, zone in Zones.ZONES do
	boundaries[i + 1] = boundaries[i] - zone.lengthStuds
end
local BiomeZone = {}
function BiomeZone.at(z: number, previous: number?): number
	if previous and previous >= 0 and previous <= #Zones.ZONES then
		local near = if previous == 0
			then math.huge
			else boundaries[previous] + Config.BOUNDARY_HYSTERESIS
		local far = if previous == #Zones.ZONES
			then -math.huge
			else boundaries[previous + 1] - Config.BOUNDARY_HYSTERESIS
		if z <= near and z > far then
			return previous
		end
	end
	if z > 0 then
		return 0
	end
	for i = 1, #Zones.ZONES do
		if z > boundaries[i + 1] then
			return i
		end
	end
	return #Zones.ZONES
end
return BiomeZone
