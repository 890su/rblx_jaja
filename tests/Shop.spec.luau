--!strict
-- Shop offers + rebirth math. Run in Studio (Edit) via MCP execute_luau.

local Shared = game:GetService("ReplicatedStorage").Shared
local ShopOffers = require(Shared.Util.ShopOffers)
local RebirthMath = require(Shared.Util.RebirthMath)
local Shop = require(Shared.Config.Shop)
local Creatures = require(Shared.Config.Creatures)

local passed = 0
local function check(name: string, ok: boolean)
	if not ok then
		error(`FAIL {name}`)
	end
	passed += 1
end

for cycle = 1, 200 do
	local a, b = ShopOffers.forCycle(cycle), ShopOffers.forCycle(cycle)
	check(`cycle {cycle} has all slots`, #a == #Shop.SLOTS)
	for slot, offer in a do
		check(`cycle {cycle} slot {slot} deterministic`, offer.creatureId == b[slot].creatureId)
		check(
			`cycle {cycle} slot {slot} rarity allowed`,
			Shop.SLOTS[slot].weights[offer.rarity] ~= nil
		)
		check(
			`cycle {cycle} slot {slot} creature matches rarity`,
			Creatures.BY_ID[offer.creatureId].rarity == offer.rarity
		)
		check(`cycle {cycle} slot {slot} price`, offer.price == Shop.PRICES[offer.rarity])
	end
end
-- Offers actually rotate between cycles.
local changed = 0
for cycle = 1, 50 do
	if ShopOffers.forCycle(cycle)[3].creatureId ~= ShopOffers.forCycle(cycle + 1)[3].creatureId then
		changed += 1
	end
end
check("offers rotate", changed > 10)
check("rebirth cost 0", RebirthMath.cost(0) == 300000)
check("rebirth cost 2", RebirthMath.cost(2) == 4800000)
check("rebirth speed 1", RebirthMath.speedRequired(1) == 10000)

return `PASS {passed}`
