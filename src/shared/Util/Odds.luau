--!strict
-- Pure weighted-rarity helpers shared by spawning (server) and odds display
-- (client), so what players see is exactly what the server rolls.

local Types = require(script.Parent.Parent.Types)

local Odds = {}

local function total(weights: Types.RarityWeights): number
	local sum = 0
	for _, weight in weights do
		sum += weight
	end
	return sum
end

-- Rolls a rarity. `order` fixes iteration order so results are reproducible
-- for a given RNG seed. `boost` multiplies every non-Common weight.
function Odds.roll(
	weights: Types.RarityWeights,
	order: { Types.Rarity },
	rng: Random,
	boost: number?
): Types.Rarity
	local boosted: Types.RarityWeights = {}
	for rarity, weight in weights do
		boosted[rarity] = if rarity ~= "Common" then weight * (boost or 1) else weight
	end
	local pick = rng:NextNumber() * total(boosted)
	local fallback: Types.Rarity = order[1]
	for i = 1, #order do
		local rarity = order[i]
		local weight = boosted[rarity]
		if weight then
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
function Odds.oneIn(weights: Types.RarityWeights, rarity: Types.Rarity): number?
	local weight = weights[rarity]
	if not weight or weight <= 0 then
		return nil
	end
	return math.max(1, math.floor(total(weights) / weight + 0.5))
end

-- Percent with sensible precision for odds windows (sum shown must be 100%).
function Odds.percent(weights: Types.RarityWeights, rarity: Types.Rarity): number
	local weight = weights[rarity] or 0
	return weight / total(weights) * 100
end

return table.freeze(Odds)
