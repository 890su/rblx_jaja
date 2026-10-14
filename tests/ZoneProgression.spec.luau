--!strict
local Shared = game.ReplicatedStorage.Shared
local Zones = require(Shared.Config.Zones)
local Rarity = require(Shared.Config.Rarity)
local Creatures = require(Shared.Config.Creatures)
local Odds = require(Shared.Util.Odds)
local HatchTime = require(Shared.Util.HatchTime)
local passed = 0
local function check(name: string, ok: boolean)
	assert(ok, name)
	passed += 1
end
local floors = { "Common", "Uncommon", "Rare", "Epic", "Legendary" }
for _, boost in { 1, 2, 3, 6, 18 } do
	local previous = 0
	for index, zone in Zones.ZONES do
		local sum, expected, baseSum = 0, 0, 0
		local observed: { [string]: number } = {}
		check("zone has strictly improving minimum", Odds.minimum(zone.weights) == floors[index])
		for _, weight in zone.weights do
			baseSum += weight
		end
		check("base odds sum to 100", math.abs(baseSum - 100) < 1e-9)
		for _, rarity in Rarity.ORDER do
			local pct = Odds.percent(zone.weights, rarity, boost)
			sum += pct
			expected += pct * Rarity.INFO[rarity].incomePerSecond / 100
			if pct > 0 then
				local pool = Creatures.candidates(rarity, index)
				check("each meteor type has multiple eligible species", #pool >= 2)
				local weightSum = 0
				for _, creature in pool do
					weightSum += Creatures.weightOf(creature, index)
				end
				local shares = 0
				for _, creature in pool do
					shares += Creatures.weightOf(creature, index) / weightSum
				end
				check("species odds sum to one", math.abs(shares - 1) < 1e-9)
			end
		end
		check("effective odds sum to 100", math.abs(sum - 100) < 1e-9)
		check("deeper zone increases expected income", expected > previous)
		previous = expected
		local rng = Random.new(9000 + index * 100 + boost)
		for _ = 1, 5000 do
			local rolled = Odds.roll(zone.weights, Rarity.ORDER, rng, boost)
			local creature = Creatures.pick(rolled, index, rng)
			check(
				"roll respects tier and species gates",
				(zone.weights[rolled] or 0) > 0
					and creature.rarity == rolled
					and creature.zone <= index
			)
			observed[rolled] = (observed[rolled] or 0) + 1
		end
		for _, rarity in Rarity.ORDER do
			check(
				"observed rolls agree with displayed odds",
				math.abs(
					(observed[rarity] or 0) / 5000 * 100 - Odds.percent(zone.weights, rarity, boost)
				) < 4
			)
		end
		local top = Rarity.ORDER[math.min(index + 2, #Rarity.ORDER)]
		check(
			"luck improves upper tier even without Common",
			Odds.percent(zone.weights, top, 2) > Odds.percent(zone.weights, top, 1)
		)
	end
end
for _, creature in Creatures.LIST do
	local reachable = false
	for index, zone in Zones.ZONES do
		if (zone.weights[creature.rarity] or 0) > 0 and Creatures.weightOf(creature, index) > 0 then
			reachable = true
		end
	end
	check("all thirty species remain obtainable in fields", reachable)
	for zone = 1, creature.zone - 1 do
		check("future species excluded", Creatures.weightOf(creature, zone) == 0)
	end
end
local zeroRng = {
	NextNumber = function()
		return 0
	end,
} :: any
check(
	"zero RNG never selects a zero-weight tier",
	Odds.roll({ Common = 0, Rare = 100 }, Rarity.ORDER, zeroRng, 2) == "Rare"
)
local now = 100000
check(
	"first pickup excludes Uncommon",
	Odds.pickupPercent(Zones.ZONES[2].weights, "Uncommon", 1, "Rare") == 0
)
check(
	"first pickup transfers lower-tier mass to Rare",
	math.abs(Odds.pickupPercent(Zones.ZONES[2].weights, "Rare", 1, "Rare") - 98) < 1e-9
)
check(
	"first pickup luck uses boosted mass",
	math.abs(Odds.pickupPercent(Zones.ZONES[2].weights, "Rare", 2, "Rare") - 126 / 130 * 100) < 1e-9
)
local legacy = {
	id = "kept",
	creatureId = "big_bang_bunny",
	rarity = "Mythic",
	paid = true,
	mutation = "Golden",
	hatchAt = now + 8 * 3600,
}
local ready = { creatureId = "pebblit", rarity = "Common", hatchAt = now - 1 }
local shorter = { creatureId = "nova_drake", rarity = "Legendary", hatchAt = now + 20 }
local profile: any = { pedestals = { ["1"] = legacy, ["2"] = ready }, storage = { shorter } }
check(
	"old eight-hour wait becomes at most ten minutes",
	HatchTime.capProfile(profile, now) == 1 and legacy.hatchAt == now + 600
)
check(
	"normalization keeps exact item and provenance",
	profile.pedestals["1"] == legacy
		and legacy.id == "kept"
		and legacy.paid == true
		and legacy.mutation == "Golden"
)
check(
	"ready and shorter waits never restart",
	ready.hatchAt == now - 1 and shorter.hatchAt == now + 20
)
check(
	"repeated load cannot extend deadline",
	HatchTime.capProfile(profile, now + 10) == 0 and legacy.hatchAt == now + 600
)
return `PASS ZoneProgression {passed}`
