--!strict
-- Track zones (GDD §4.2). Weights are percentages per zone (sum = 100) and are
-- the single source for both spawning and the in-game odds display.

local Types = require(script.Parent.Parent.Types)
local deepFreeze = require(script.Parent.Parent.Util.deepFreeze)

local ZONES: { Types.ZoneInfo } = {
	{
		index = 1,
		speedGate = 0,
		rebirthGate = 0,
		-- Shorter: a newcomer at 16 studs/s crosses it in ~30 s, and it hosts
		-- the Void Run corridor (~15 s at corridor pace).
		lengthStuds = 500,
		maxMeteors = 10,
		spawnIntervalSeconds = 4,
		weights = { Common = 80, Uncommon = 18, Rare = 2 },
	},
	{
		index = 2,
		speedGate = 100,
		rebirthGate = 0,
		lengthStuds = 1000,
		maxMeteors = 8,
		spawnIntervalSeconds = 5,
		weights = { Uncommon = 70, Rare = 28, Epic = 2 },
	},
	{
		index = 3,
		speedGate = 500,
		rebirthGate = 0,
		lengthStuds = 1000,
		maxMeteors = 8,
		spawnIntervalSeconds = 6,
		weights = { Rare = 70, Epic = 28, Legendary = 2 },
	},
	{
		index = 4,
		speedGate = 2000,
		rebirthGate = 0,
		lengthStuds = 1000,
		maxMeteors = 6,
		spawnIntervalSeconds = 7,
		weights = {
			Epic = 75,
			Legendary = 24,
			Mythic = 1,
		},
	},
	{
		index = 5,
		speedGate = 8000,
		rebirthGate = 1,
		lengthStuds = 1000,
		maxMeteors = 6,
		spawnIntervalSeconds = 8,
		weights = {
			Legendary = 90,
			Mythic = 10,
		},
	},
}

export type Config = {
	ZONES: { Types.ZoneInfo },
	FIRST_VISIT_GUARANTEE: { zone: number, rarity: Types.Rarity },
}

local config: Config = {
	ZONES = ZONES,
	FIRST_VISIT_GUARANTEE = { zone = 2, rarity = "Rare" }, -- FTUE beat
}

return deepFreeze(config)
