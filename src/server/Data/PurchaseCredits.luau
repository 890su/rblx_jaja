--!strict
-- A paid effect survives an inventory/cycle change during checkout.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Credits = {}
function Credits.apply(
	profile: Types.PlayerProfile,
	key: string,
	now: number,
	cycle: number
): boolean
	if key == "InstantHatch" then
		local changed = false
		local function hatch(collection: { [any]: Types.PedestalState })
			for _, state in collection do
				if state.hatchAt and state.hatchAt > now then
					state.hatchAt = now
					changed = true
				end
			end
		end
		hatch(profile.pedestals)
		hatch(profile.storage)
		return changed
	elseif key == "Restock" then
		if profile.shop.cycle ~= cycle or next(profile.shop.bought) == nil then
			return false
		end
		profile.shop.bought = {}
		return true
	end
	return false
end
function Credits.use(profile: Types.PlayerProfile, key: string, now: number, cycle: number): boolean
	local count = if key == "InstantHatch"
		then profile.hatchCredits
		elseif key == "Restock" then profile.restockCredits
		else 0
	if count <= 0 or not Credits.apply(profile, key, now, cycle) then
		return false
	end
	if key == "InstantHatch" then
		profile.hatchCredits -= 1
	else
		profile.restockCredits -= 1
	end
	return true
end
return Credits
