--!strict
-- Visible egg guards in every zone. Only a clearly telegraphed, locked dash
-- can knock an egg out of a carrier's hands; approaching/touching is safe.

local deepFreeze = require(script.Parent.Parent.Util.deepFreeze)

local config = {
	FROM_ZONE = 1,
	COUNT_BY_ZONE = { 1, 2, 2, 3, 4 }, -- chasers after pickup (before rarity extras)
	GUARDS_BY_ZONE = { 1, 2, 2, 2, 2 }, -- patrolling guards per egg before pickup
	EXTRA_BY_RARITY = { Epic = 1, Legendary = 1, Mythic = 2 } :: { [string]: number },
	SPEED_FACTOR = 0.7,
	MIN_SPEED = 12,
	MAX_CHASE_SPEED = 40,
	FIRST_TIME_FACTOR = 0.55,
	PICKUP_GRACE = 1.5,
	WARNING_SECONDS = 0.9,
	FIRST_ZONE_WARNING_SECONDS = 1.25,
	RECOVERY_SECONDS = 1.4,
	ATTACK_RANGE = 22,
	STANDOFF_DISTANCE = 13,
	DASH_DISTANCE = 27,
	DASH_SPEED = 65,
	FIRST_ZONE_DASH_SPEED = 42,
	HIT_RADIUS = 2.8,
	PATROL_RADIUS = 8,
	SERVER_TICK = 1 / 30,
	GIVE_UP_SECONDS = 30,
	HOVER_HEIGHT = 3.5,
	MAX_CHASERS_PER_PLAYER = 4,
	-- Void Hound: from this zone, a guard tears open a portal on pickup and a
	-- hound leaps out to chase on foot (same telegraphed pounce as drones).
	HOUND_FROM_ZONE = 3,
	HOUND_FACTOR = 0.8,
	PORTAL_SECONDS = 0.7,
	-- Idle guards with no player this close skip their patrol updates.
	GUARD_ACTIVE_RADIUS = 300,
	MAX_ACTIVE = 140, -- two guards per egg + shower guards + chasers and hounds
}

return deepFreeze(config)
