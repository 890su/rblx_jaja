--!strict
-- Station, income, rebirth and save tuning (GDD §4.4, §4.6, §7).

local deepFreeze = require(script.Parent.Parent.Util.deepFreeze)

return deepFreeze({
	SERVER_SIZE = 8,
	INCOME_TICK_SECONDS = 1,

	PEDESTALS_START = 3,
	PEDESTALS_MAX_COINS = 8,
	PEDESTAL_COSTS = { 500, 2500, 10000, 60000, 250000 }, -- pedestals 4..8 (tools/balance_sim.py)
	SELL_SECONDS = 30, -- replaced creature sells for income * SELL_SECONDS
	PEDESTALS_EXPANSION_PASS = 2,

	OFFLINE_RATE = 0.25,
	OFFLINE_CAP_HOURS = 12,
	OFFLINE_RATE_PASS = 0.5,
	OFFLINE_CAP_HOURS_PASS = 24,

	REBIRTH_BASE_COST = 300000,
	REBIRTH_COST_GROWTH = 4, -- cost = BASE * GROWTH ^ rebirths
	REBIRTH_SPEED_REQUIREMENT = 5000, -- * (rebirths + 1)

	-- "Run Training" coin upgrade: +BONUS speed gain per level.
	TRAINING_BASE_COST = 2000,
	TRAINING_COST_GROWTH = 2.2,
	TRAINING_BONUS = 0.10,
	TRAINING_MAX = 10,
	REBIRTH_INCOME_BONUS = 0.5, -- additive per rebirth

	VIP_COIN_BONUS = 0.5,
	COINS_PASS_MULTIPLIER = 2,

	AUTOSAVE_SECONDS = 60,
})
