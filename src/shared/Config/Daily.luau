--!strict
-- 7-day login streak (GDD §4.10). Missing a day restarts at day 1; nothing
-- already earned is ever taken away.

local deepFreeze = require(script.Parent.Parent.Util.deepFreeze)

export type Reward = { coins: number?, creatureId: string?, shieldMinutes: number?, label: string }

local REWARDS: { Reward } = {
	{ coins = 300, label = "300 Stardust" },
	{ creatureId = "emberfox", label = "Emberfox (Uncommon)" },
	{ coins = 2000, label = "2,000 Stardust" },
	{ shieldMinutes = 30, label = "30 min Shield" },
	{ creatureId = "nebula_newt", label = "Nebula Newt (Rare)" },
	{ coins = 15000, label = "15,000 Stardust" },
	{ creatureId = "plasma_panda", label = "Plasma Panda (Epic)" },
}

export type Config = { REWARDS: { Reward } }
local config: Config = { REWARDS = REWARDS }
return deepFreeze(config)
