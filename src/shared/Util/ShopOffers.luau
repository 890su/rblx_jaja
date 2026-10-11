--!strict
-- Pure, deterministic shop offers for a restock cycle: every server (and the
-- client) derives the same offers from the cycle number alone.

local Types = require(script.Parent.Parent.Types)
local Shop = require(script.Parent.Parent.Config.Shop)
local Rarity = require(script.Parent.Parent.Config.Rarity)
local Creatures = require(script.Parent.Parent.Config.Creatures)
local Odds = require(script.Parent.Odds)

local ShopOffers = {}

function ShopOffers.forCycle(cycle: number): { Types.ShopOffer }
	local offers: { Types.ShopOffer } = {}
	for slot, slotConfig in Shop.SLOTS do
		local rng = Random.new(cycle * 7919 + slot * 104729)
		local rarity = Odds.roll(slotConfig.weights, Rarity.ORDER, rng)
		local creature = Creatures.pick(rarity, rng:NextInteger(1, 5), rng)
		offers[slot] = {
			slot = slot,
			creatureId = creature.id,
			rarity = rarity,
			price = Shop.PRICES[rarity],
			stock = slotConfig.stock,
		}
	end
	return offers
end

return table.freeze(ShopOffers)
