--!strict
-- Crater Canyons (GDD §4.2b): maze pockets beside the speed lane in deep zones.

local deepFreeze = require(script.Parent.Parent.Util.deepFreeze)

return deepFreeze({
	FROM_ZONE = 3, -- zones before this stay straight (FTUE)
	LANE_WIDTH = 80, -- central speed lane, studs
	CELL = 48, -- maze cell size, studs
	WALL_HEIGHT = 28,
	WALL_THICKNESS = 3,
	BRAID = 0.35, -- extra wall removal probability (loops)
	LANE_OPENING_EVERY = 4, -- one opening to the lane per N cells along the zone
	SPAWN_SHARE = 0.7, -- share of meteors spawned inside canyons
	RARITY_BOOST = 2, -- non-Common weight multiplier for canyon spawns
	RESEED_PERIOD = 24 * 60 * 60, -- layout reshuffles every UTC day
})
