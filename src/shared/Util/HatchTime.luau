--!strict
-- Monotonic compatibility for old incubators: never restart or lengthen one.
local Types = require(script.Parent.Parent.Types)
local Rarity = require(script.Parent.Parent.Config.Rarity)
local HatchTime = {}

local function cap(state: Types.PedestalState, now: number): boolean
	local info = Rarity.INFO[state.rarity]
	if info and state.hatchAt and state.hatchAt > now + info.hatchSeconds then
		state.hatchAt = now + info.hatchSeconds
		return true
	end
	return false
end

function HatchTime.capProfile(profile: Types.PlayerProfile, now: number): number
	local changed = 0
	for _, state in profile.pedestals do
		if cap(state, now) then
			changed += 1
		end
	end
	for _, state in profile.storage do
		if cap(state, now) then
			changed += 1
		end
	end
	return changed
end

return table.freeze(HatchTime)
