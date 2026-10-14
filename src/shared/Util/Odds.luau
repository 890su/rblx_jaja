--!strict
-- Pure weighted-rarity helpers shared by spawning (server) and odds display
-- (client), so what players see is exactly what the server rolls.

local Types = require(script.Parent.Parent.Types)
local Rarity = require(script.Parent.Parent.Config.Rarity)

local Odds = {}

local function total(weights: Types.RarityWeights): number
	local sum = 0
	for _, weight in weights do
		sum += weight
	end
	return sum
end

-- The lowest positive tier is the baseline, even in a zone without Common.
function Odds.minimum(weights: Types.RarityWeights): Types.Rarity
	for _, rarity in Rarity.ORDER do
		if (weights[rarity] or 0) > 0 then
			return rarity
		end
	end
	error("rarity weights have no positive entries")
end

local function boosted(weights: Types.RarityWeights, boost: number?): Types.RarityWeights
	if not boost or boost == 1 then
		return weights
	end
	local floor = Odds.minimum(weights)
	local out: Types.RarityWeights = {}
	for rarity, weight in weights do
		out[rarity] = if rarity ~= floor then weight * boost else weight
	end
	return out
end

-- Rolls a rarity. `order` fixes iteration order so results are reproducible
-- for a given RNG seed. Boost only raises tiers above the local minimum.
function Odds.roll(
	weights: Types.RarityWeights,
	order: { Types.Rarity },
	rng: Random,
	boost: number?
): Types.Rarity
	local effective = boosted(weights, boost)
	assert(total(effective) > 0, "rarity weights have no positive entries")
	local pick = rng:NextNumber() * total(effective)
	local fallback: Types.Rarity = order[1]
	for i = 1, #order do
		local rarity = order[i]
		local weight = effective[rarity]
		if weight and weight > 0 then
			fallback = rarity
			pick -= weight
			if pick <= 0 then
				return rarity
			end
		end
	end
	return fallback
end

-- "1 in X" for display; nil if the rarity can't appear with these weights.
function Odds.oneIn(weights: Types.RarityWeights, rarity: Types.Rarity, boost: number?): number?
	weights = boosted(weights, boost)
	local weight = weights[rarity]
	if not weight or weight <= 0 then
		return nil
	end
	return math.max(1, math.floor(total(weights) / weight + 0.5))
end

-- Percent with sensible precision for odds windows (sum shown must be 100%).
function Odds.percent(weights: Types.RarityWeights, rarity: Types.Rarity, boost: number?): number
	weights = boosted(weights, boost)
	local weight = weights[rarity] or 0
	return weight / total(weights) * 100
end

-- First-pickup upgrade transfers lower-tier probability into the guaranteed
-- tier before the species roll, exactly as MeteorService does.
function Odds.pickupPercent(
	weights: Types.RarityWeights,
	rarity: Types.Rarity,
	boost: number?,
	guarantee: Types.Rarity?
): number
	if not guarantee then
		return Odds.percent(weights, rarity, boost)
	end
	local order, floor = Rarity.INFO[rarity].order, Rarity.INFO[guarantee].order
	if order < floor then
		return 0
	end
	if order > floor then
		return Odds.percent(weights, rarity, boost)
	end
	local sum = 0
	for candidate, info in Rarity.INFO do
		if info.order <= floor then
			sum += Odds.percent(weights, candidate, boost)
		end
	end
	return sum
end

return table.freeze(Odds)
