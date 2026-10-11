--!strict
-- Global-clock schedules (GDD §4.7–4.8). All periods in seconds of server time.

local deepFreeze = require(script.Parent.Parent.Util.deepFreeze)

return deepFreeze({
	SHOP_RESTOCK_PERIOD = 5 * 60,
	SHOP_SLOTS = 6,
	CRATE_ROTATION_PERIOD = 30 * 60,

	SHOWER_PERIOD = 15 * 60,
	SHOWER_DURATION = 60,
	SHOWER_WARNING = 60,
	SHOWER_METEORS = 12,
	SHOWER_RARITY_BOOST = 3,
	SHOWER_ZONES = { 3, 4, 5 },
})
