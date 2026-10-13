--!strict
-- Rewards and receipt marker are one mutation, independent of UI/analytics.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Products = require(Shared.Config.Products)
local Creatures = require(Shared.Config.Creatures)
local Credits = require(script.Parent.PurchaseCredits)
local Clock = require(Shared.Clock)
local Events = require(Shared.Config.Events)
local PurchaseGrants = {}

function PurchaseGrants.apply(
	profile: Types.PlayerProfile,
	key: string,
	receipt: string,
	ids: { string },
	now: number,
	luckUntil: number,
	newId: () -> string
): boolean
	if profile.purchases[receipt] then
		return false
	end
	local storage = table.clone(profile.storage)
	for _, id in ids do
		local creature = assert(Creatures.BY_ID[id], "unknown purchase creature")
		table.insert(
			storage,
			{ id = newId(), creatureId = id, rarity = creature.rarity, paid = true }
		)
	end
	local pedestals = table.clone(profile.pedestals)
	local flags = table.clone(profile.flags)
	local purchases = table.clone(profile.purchases)
	local shieldUntil = profile.shieldUntil
	if key == "StarterPack" then
		flags.starterPack = true
		shieldUntil = math.max(shieldUntil, now) + Products.STARTER_SHIELD_SECONDS
	elseif key == "Shield15" then
		shieldUntil = math.max(shieldUntil, now) + Products.SHIELD_SECONDS
	end
	purchases[receipt] = now
	-- All potentially failing work is finished; these writes cannot yield.
	profile.storage, profile.pedestals = storage, pedestals
	profile.flags, profile.purchases = flags, purchases
	profile.shieldUntil = shieldUntil
	if key == "Restock" or key == "InstantHatch" then
		if not Credits.apply(profile, key, now, Clock.cycleIndex(Events.SHOP_RESTOCK_PERIOD)) then
			if key == "InstantHatch" then
				profile.hatchCredits = (profile.hatchCredits or 0) + 1
			else
				profile.restockCredits = (profile.restockCredits or 0) + 1
			end
		end
	end
	if key == "ServerLuck" and #ids == 0 then
		profile.serverLuckUntil = luckUntil
	end
	return true
end

return PurchaseGrants
