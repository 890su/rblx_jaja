--!strict
-- Stable creature ids and rarities; zone is the first field zone for this
-- species. Higher zones retain earlier eligible species with lower weights.
-- Every available rarity has several species, never a single forced hatch.
-- Display names live in Theme.

local Types = require(script.Parent.Parent.Types)
local deepFreeze = require(script.Parent.Parent.Util.deepFreeze)

export type Creature = { id: string, rarity: Types.Rarity, zone: number }

local LIST: { Creature } = {
	{ id = "pebblit", rarity = "Common", zone = 1 },
	{ id = "dustbun", rarity = "Common", zone = 1 },
	{ id = "cindermite", rarity = "Common", zone = 1 },
	{ id = "glowgrub", rarity = "Common", zone = 1 },
	{ id = "rockroo", rarity = "Common", zone = 1 },

	{ id = "emberfox", rarity = "Uncommon", zone = 1 },
	{ id = "sparkle_snail", rarity = "Uncommon", zone = 1 },
	{ id = "crater_crab", rarity = "Uncommon", zone = 2 },
	{ id = "moon_moth", rarity = "Uncommon", zone = 2 },
	{ id = "pulsar_pup", rarity = "Uncommon", zone = 2 },

	{ id = "frostfin", rarity = "Rare", zone = 1 },
	{ id = "comet_cat", rarity = "Rare", zone = 1 },
	{ id = "nebula_newt", rarity = "Rare", zone = 2 },
	{ id = "orbit_owl", rarity = "Rare", zone = 3 },
	{ id = "quartz_quokka", rarity = "Rare", zone = 3 },

	{ id = "void_viper", rarity = "Epic", zone = 2 },
	{ id = "solar_stag", rarity = "Epic", zone = 2 },
	{ id = "plasma_panda", rarity = "Epic", zone = 3 },
	{ id = "aurora_axolotl", rarity = "Epic", zone = 4 },
	{ id = "ion_ibex", rarity = "Epic", zone = 4 },

	{ id = "nova_drake", rarity = "Legendary", zone = 3 },
	{ id = "galaxy_griffin", rarity = "Legendary", zone = 3 },
	{ id = "eclipse_lynx", rarity = "Legendary", zone = 4 },
	{ id = "starlight_seraph", rarity = "Legendary", zone = 5 },
	{ id = "meteor_mammoth", rarity = "Legendary", zone = 5 },

	{ id = "cosmic_leviathan", rarity = "Mythic", zone = 4 },
	{ id = "quasar_phoenix", rarity = "Mythic", zone = 4 },
	{ id = "singularity_sprite", rarity = "Mythic", zone = 5 },
	{ id = "celestial_kirin", rarity = "Mythic", zone = 5 },
	{ id = "big_bang_bunny", rarity = "Mythic", zone = 5 },
}

local BY_ID: { [string]: Creature } = {}
for _, creature in LIST do
	assert(BY_ID[creature.id] == nil, `duplicate creature id {creature.id}`)
	BY_ID[creature.id] = creature
end

-- Exact eligible pool used by field RNG and its odds display.
local function candidates(rarity: Types.Rarity, zone: number): { Creature }
	local pool = {}
	for _, creature in LIST do
		if creature.rarity == rarity and creature.zone <= zone then
			table.insert(pool, creature)
		end
	end
	return pool
end

local function weightOf(creature: Creature, zone: number): number
	if creature.zone > zone then
		return 0
	end
	local distance = zone - creature.zone
	return if distance == 0 then 4 elseif distance == 1 then 2 else 1
end

local function pick(rarity: Types.Rarity, zone: number, rng: Random): Creature
	local pool = candidates(rarity, zone)
	local total = 0
	for _, creature in pool do
		total += weightOf(creature, zone)
	end
	assert(#pool > 0, `no creature for rarity {rarity}`)
	local roll = rng:NextNumber() * total
	for _, creature in pool do
		roll -= weightOf(creature, zone)
		if roll <= 0 then
			return creature
		end
	end
	return pool[#pool]
end

export type Config = {
	LIST: { Creature },
	BY_ID: { [string]: Creature },
	candidates: (rarity: Types.Rarity, zone: number) -> { Creature },
	pick: (rarity: Types.Rarity, zone: number, rng: Random) -> Creature,
	weightOf: (creature: Creature, zone: number) -> number,
}

local config: Config = {
	LIST = LIST,
	BY_ID = BY_ID,
	candidates = candidates,
	pick = pick,
	weightOf = weightOf,
}

return deepFreeze(config)
