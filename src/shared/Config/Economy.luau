--!strict
-- Station, income, rebirth and save tuning (GDD §4.4, §4.6, §7).

local deepFreeze = require(script.Parent.Parent.Util.deepFreeze)

return deepFreeze({
	SERVER_SIZE = 8,
	INCOME_TICK_SECONDS = 1,

	PEDESTALS_START = 3,
	PEDESTALS_MAX_COINS = 6,
	PEDESTAL_COSTS = { 500, 2500, 10000 }, -- pedestals 4, 5, 6
	PEDESTALS_EXPANSION_PASS = 2,

	OFFLINE_RATE = 0.25,
	OFFLINE_CAP_HOURS = 12,
	OFFLINE_RATE_PASS = 0.5,
	OFFLINE_CAP_HOURS_PASS = 24,

	REBIRTH_BASE_COST = 5000,
	REBIRTH_COST_GROWTH = 4, -- cost = BASE * GROWTH ^ rebirths
	REBIRTH_SPEED_REQUIREMENT = 10000, -- * (rebirths + 1)
	REBIRTH_INCOME_BONUS = 0.5, -- additive per rebirth

	VIP_COIN_BONUS = 0.5,
	COINS_PASS_MULTIPLIER = 2,

	AUTOSAVE_SECONDS = 60,
})
