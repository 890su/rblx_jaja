--!strict
-- Egg guards (GDD §4.5b). Guards roam around their egg sweeping a searchlight
-- beam; a carrier caught in a beam fills the guard's alert meter (yellow) and
-- a full meter starts the chase (red). Only telegraphed attacks — the locked
-- dash, and from the attack zone Undertale-style ground attacks — can knock an
-- egg out of a carrier's hands; approaching/touching is safe.

local deepFreeze = require(script.Parent.Parent.Util.deepFreeze)

local config = {
	FROM_ZONE = 1,
	COUNT_BY_ZONE = { 1, 2, 2, 3, 4 }, -- chasers once spotted (before rarity extras)
	GUARDS_BY_ZONE = { 1, 2, 2, 2, 2 }, -- patrolling guards per egg
	EXTRA_BY_RARITY = { Epic = 1, Legendary = 1, Mythic = 2 } :: { [string]: number },
	SPEED_FACTOR = 0.7,
	MIN_SPEED = 12,
	MAX_CHASE_SPEED = 40,
	FIRST_TIME_FACTOR = 0.55,
	PICKUP_GRACE = 1.5, -- chase start -> first possible attack
	WARNING_SECONDS = 0.9,
	FIRST_ZONE_WARNING_SECONDS = 1.25,
	RECOVERY_SECONDS = 1.4,
	ATTACK_RANGE = 22,
	STANDOFF_DISTANCE = 13,
	DASH_DISTANCE = 27,
	DASH_SPEED = 65,
	FIRST_ZONE_DASH_SPEED = 42,
	HIT_RADIUS = 2.8,
	SERVER_TICK = 1 / 30,
	GIVE_UP_SECONDS = 30,
	HOVER_HEIGHT = 3.5,
	MAX_CHASERS_PER_PLAYER = 4,

	-- Patrol: smooth, noisy roaming between these distances from the egg.
	PATROL_MIN_RADIUS = 14,
	PATROL_MAX_RADIUS = 38,
	PATROL_SPEED = 9,
	ORPHAN_SECONDS = 25, -- guards of a taken egg keep patrolling this long
	-- Vision: a sector on the ground in front of the guard, plus a small
	-- all-round "hearing" circle so nobody can sneak right up behind it.
	VISION_RANGE = 26,
	VISION_HALF_ANGLE = math.rad(50),
	HEARING_RADIUS = 8,
	VISION_SWEEP = 0.7, -- radians either side of the travel direction
	-- Alert meter (0..1): fills while a carrier is seen.
	ALERT_FILL_MOVING = 1 / 0.5, -- per second
	ALERT_FILL_STILL = 1 / 1.2,
	ALERT_FIRST_ZONE_SCALE = 0.7,
	ALERT_DECAY = 0.8,
	ALERT_TURN_RATE = math.rad(100), -- tracking turn speed while alert
	ALARM_RADIUS = 55, -- guards this close join when one starts a chase
	-- Pickup noise: guards this close always hear it; from the noisy zone the
	-- radius grows. Heard guards start alert with a half-full meter.
	PICKUP_HEARING_RADIUS = 16,
	NOISY_FROM_ZONE = 3,
	NOISE_RADIUS = 45,
	NOISE_ALERT = 0.5,

	-- Ground attacks (Undertale-style, shared ArenaPatterns math) cast by
	-- chasing guards from this zone, in addition to the dash.
	ATTACKS_FROM_ZONE = 3,
	ATTACK_KINDS = { "spears", "ring", "wall", "blaster" },
	ATTACK_EVERY_BY_ZONE = { 0, 0, 3.2, 2.7, 2.2 }, -- seconds between casts
	ATTACK_MAX_LEVEL = 0.6, -- keeps telegraphs >= ~0.7 s in the open field
	ATTACK_CAST_RANGE = 150, -- fast carriers outrun drones; attacks still reach
	ATTACK_MAX_LEAD = 120, -- studs of path prediction (carry pace ~90 studs/s in zone 3)

	-- Reclaim: a dropped egg left alone this long is fetched by a drone and
	-- flown back to its zone (slowly, so it can be snatched back on the way).
	RECLAIM_DELAY = 5,
	RECLAIM_SEARCH_RADIUS = 150, -- idle guards this close answer; else one flies in
	RECLAIM_FLY_SPEED = 30,
	RECLAIM_CARRY_SPEED = 16,
	RECLAIM_REST_SECONDS = 180, -- lifetime of the egg once it is back

	-- Void Hound: from this zone, the guard that starts a chase tears open a
	-- portal and a hound leaps out to chase on foot.
	HOUND_FROM_ZONE = 3,
	HOUND_FACTOR = 0.8,
	PORTAL_SECONDS = 0.7,
	-- Idle guards with no player this close skip their patrol updates.
	GUARD_ACTIVE_RADIUS = 300,
	MAX_ACTIVE = 160, -- two guards per egg + orphans + shower guards + chasers
}

return deepFreeze(config)
