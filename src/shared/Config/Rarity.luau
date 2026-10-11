--!strict
-- Rarities and mutations (GDD §4.3). Display odds as "1 in X".

local Types = require(script.Parent.Parent.Types)
local deepFreeze = require(script.Parent.Parent.Util.deepFreeze)

local ORDER: { Types.Rarity } = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }

local INFO: { [string]: Types.RarityInfo } = {
	Common = { order = 1, incomePerSecond = 1, hatchSeconds = 10 },
	Uncommon = { order = 2, incomePerSecond = 4, hatchSeconds = 60 },
	Rare = { order = 3, incomePerSecond = 15, hatchSeconds = 5 * 60 },
	Epic = { order = 4, incomePerSecond = 60, hatchSeconds = 20 * 60 },
	Legendary = { order = 5, incomePerSecond = 250, hatchSeconds = 60 * 60 },
	Mythic = { order = 6, incomePerSecond = 1200, hatchSeconds = 8 * 60 * 60 },
}

local MUTATIONS = {
	Golden = { chance = 0.02, incomeMultiplier = 2, onlineOnly = false },
	Starborn = { chance = 0, incomeMultiplier = 3, onlineOnly = true }, -- Starfall event only
}

export type Config = {
	ORDER: { Types.Rarity },
	INFO: { [string]: Types.RarityInfo },
	MUTATIONS: typeof(MUTATIONS),
}

local config: Config = {
	ORDER = ORDER,
	INFO = INFO,
	MUTATIONS = MUTATIONS,
}

return deepFreeze(config)
