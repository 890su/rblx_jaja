--!strict
-- Creature roster v1 (GDD §4.3): 5 per rarity, each with a home zone. A meteor
-- of rarity R picked up in zone Z hatches a creature of rarity R from zone Z's
-- pool (fallback: nearest lower zone, then any). Display names live in Theme.

local Types = require(script.Parent.Parent.Types)
local deepFreeze = require(script.Parent.Parent.Util.deepFreeze)

export type Creature = { id: string, rarity: Types.Rarity, zone: number }

local LIST: { Creature } = {
	{ id = "pebblit", rarity = "Common", zone = 1 },
	{ id = "dustbun", rarity = "Common", zone = 2 },
	{ id = "cindermite", rarity = "Common", zone = 3 },
	{ id = "glowgrub", rarity = "Common", zone = 4 },
	{ id = "rockroo", rarity = "Common", zone = 5 },

	{ id = "emberfox", rarity = "Uncommon", zone = 1 },
	{ id = "sparkle_snail", rarity = "Uncommon", zone = 2 },
	{ id = "crater_crab", rarity = "Uncommon", zone = 3 },
	{ id = "moon_moth", rarity = "Uncommon", zone = 4 },
	{ id = "pulsar_pup", rarity = "Uncommon", zone = 5 },

	{ id = "frostfin", rarity = "Rare", zone = 1 },
	{ id = "comet_cat", rarity = "Rare", zone = 2 },
	{ id = "nebula_newt", rarity = "Rare", zone = 3 },
	{ id = "orbit_owl", rarity = "Rare", zone = 4 },
	{ id = "quartz_quokka", rarity = "Rare", zone = 5 },

	{ id = "void_viper", rarity = "Epic", zone = 2 },
	{ id = "solar_stag", rarity = "Epic", zone = 3 },
	{ id = "plasma_panda", rarity = "Epic", zone = 4 },
	{ id = "aurora_axolotl", rarity = "Epic", zone = 5 },
	{ id = "ion_ibex", rarity = "Epic", zone = 5 },

	{ id = "nova_drake", rarity = "Legendary", zone = 3 },
	{ id = "galaxy_griffin", rarity = "Legendary", zone = 4 },
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

-- Candidates for a rarity rolled in a zone: same zone first, else the closest
-- lower zone that has one, else any creature of that rarity.
local function candidates(rarity: Types.Rarity, zone: number): { Creature }
	for z = zone, 1, -1 do
		local found = {}
		for _, creature in LIST do
			if creature.rarity == rarity and creature.zone == z then
				table.insert(found, creature)
			end
		end
		if #found > 0 then
			return found
		end
	end
	local any = {}
	for _, creature in LIST do
		if creature.rarity == rarity then
			table.insert(any, creature)
		end
	end
	return any
end

local function pick(rarity: Types.Rarity, zone: number, rng: Random): Creature
	local pool = candidates(rarity, zone)
	assert(#pool > 0, `no creature for rarity {rarity}`)
	return pool[rng:NextInteger(1, #pool)]
end

export type Config = {
	LIST: { Creature },
	BY_ID: { [string]: Creature },
	candidates: (rarity: Types.Rarity, zone: number) -> { Creature },
	pick: (rarity: Types.Rarity, zone: number, rng: Random) -> Creature,
}

local config: Config = {
	LIST = LIST,
	BY_ID = BY_ID,
	candidates = candidates,
	pick = pick,
}

return deepFreeze(config)
