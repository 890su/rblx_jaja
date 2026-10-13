--!strict
-- Egg guards (GDD §4.5b). Guards roam around their egg sweeping a searchlight
-- beam; a carrier caught in a beam fills the guard's alert meter (yellow) and
-- a full meter starts the chase (red). Only telegraphed attacks — the locked
-- dash, and from the attack zone Undertale-style ground attacks — can knock an
-- egg out of a carrier's hands; approaching/touching is safe.

local deepFreeze = require(script.Parent.Parent.Util.deepFreeze)

local config = {
	FROM_ZONE = 1,
	COUNT_BY_ZONE = { 1, 2, 3, 4, 4 },
	ZONE_CHASER_CAP = { 1, 2, 3, 4, 4 }, -- rarity never bypasses the zone budget
	GUARDS_BY_ZONE = { 1, 2, 2, 2, 2 }, -- patrolling guards per egg
	EXTRA_BY_RARITY = { Epic = 1, Legendary = 1, Mythic = 2 } :: { [string]: number },
	SPEED_FACTOR = 0.7,
	MIN_SPEED = 12,
	MAX_CHASE_SPEED = 40,
	-- Roles scale only part of the carrier's upgrade speed; relay guards ahead
	-- supply interception instead of every pursuer outrunning the player.
	ROLE_SPEED = { pressure = 0.82, flank = 0.94, intercept = 1.06 },
	ROLE_BASE_SPEED = 12,
	ROLE_SPEED_SCALE = 0.72,
	ROLE_MAX_SPEED = 210,
	FORMATION = {
		trailDistance = 20,
		flankDistance = 25,
		flankAhead = 8,
		interceptSeconds = 0.45,
		minLead = 24,
		maxLead = 95,
	},
	STEERING = { acceleration = 180, turnRate = math.rad(170), arrivalSeconds = 0.3 },
	HEADING_TURN_RATE = math.rad(100),
	HEADING_MIN_SPEED = 3,
	SEPARATION_DISTANCE = 14,
	SEPARATION_WEIGHT = 1.6,
	RECOVERY_SPEED_FACTOR = 0.65,
	GROUP_RECOVERY_SECONDS = 0.7,
	RELAY_TICK = 0.2,
	MOTION_TICK = 0.1,
	MOTION_REACH = 650,
	MOTION_DRAW_DISTANCE = 450,
	MOTION_STALE_SECONDS = 3,
	MOTION_INTERPOLATION_SECONDS = 0.1,
	MOTION_EXTRAPOLATION_SECONDS = 0.12,
	MOTION_PHASE_BLEND_SECONDS = 0.12,
	MAX_FRAME_DT = 0.15,
	TRACK_HALF_WIDTH = 278,
	TRACK_MIN_Z = -4498,
	FIRST_TIME_FACTOR = 0.55,
	PICKUP_GRACE = 1.5, -- chase start -> first possible attack
	-- Dash: a yellow laser sight tracks where the carrier will be, turns red
	-- and freezes for LOCK_SECONDS, then the drone dashes along it.
	WARNING_SECONDS = 0.9, -- whole telegraph, lock included
	FIRST_ZONE_WARNING_SECONDS = 1.25,
	LOCK_SECONDS = 0.35,
	RECOVERY_SECONDS = 1.4,
	ATTACK_RANGE = 34, -- the predicted target this close starts the telegraph
	STANDOFF_DISTANCE = 13,
	DASH_DISTANCE = 46, -- at the base speed; faster dashes reach further
	DASH_SPEED = 115,
	FIRST_ZONE_DASH_SPEED = 75,
	-- A dash is always this much faster than the carrier is running, and lasts
	-- about DASH_SECONDS, so a fast runner faces a longer, faster dash (and
	-- ATTACK_RANGE grows with it).
	DASH_SPEED_FACTOR = 1.4,
	DASH_SECONDS = 0.4,
	-- Hit radius grows with dash speed (a fast runner crosses 2.8 studs in a
	-- fraction of a server tick): at least HIT_RADIUS, else speed x this.
	DASH_HIT_SECONDS = 0.025,
	FIRST_ZONE_DASH_PREDICT = 0.5, -- share of the runner's lead aimed for in zone 1
	DASH_MAX_LEAD = 260, -- studs of path prediction for the dash (fast carriers need ~1.3 s)
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
	VISION_RANGE = 52,
	VISION_HALF_ANGLE = math.rad(50),
	HEARING_RADIUS = 8,
	VISION_SWEEP = 0.7, -- radians either side of the travel direction
	-- A guard that sees a carrier gives chase at once. The alert meter (0..1)
	-- is only for a pickup it heard: it turns to look and calms down over time.
	ALERT_DECAY = 0.8,
	ALERT_TURN_RATE = math.rad(100), -- tracking turn speed while alert
	ALARM_RADIUS = 55, -- guards this close join when one starts a chase
	-- Relay: during a chase an alarm line runs ahead of the carrier; idle
	-- guards it touches join the chase, and chasers left far behind hand off
	-- and return to their posts.
	-- (Not during a player's very first chase.)
	RELAY_AHEAD_SECONDS = 2.2, -- the line runs this much travel time ahead
	RELAY_MIN_AHEAD = 60,
	RELAY_MAX_AHEAD = 260,
	RELAY_HALF_WIDTH = 90, -- the line's reach either side of the path
	RELAY_MAX_CHASERS = 4,
	RELAY_DROP_DISTANCE = 110,
	RELAY_GRACE = 0.3, -- seconds before a relayed guard may aim
	-- Pickup noise: guards this close always hear it; from the noisy zone the
	-- radius grows. Heard guards start alert with a half-full meter.
	PICKUP_HEARING_RADIUS = 16,
	NOISY_FROM_ZONE = 3,
	NOISE_RADIUS = 45,
	NOISE_ALERT = 0.5,

	-- Drone attacks besides the dash (Undertale-style, shared ArenaPatterns
	-- math): a chasing drone in reach of the runner's predicted spot fires one.
	-- Kinds unlock by zone; the level (density, speed, shorter telegraphs)
	-- rises with the egg's rarity and as the chase drags on.
	ATTACKS_FROM_ZONE = 2,
	ATTACK_UNLOCKS = { bombs = 2, spears = 2, spiral = 3, ring = 3, laser = 4 } :: { [string]: number },
	-- How far the casting drone may be from the target spot.
	ATTACK_REACH = { bombs = 90, spiral = 55, laser = 42, spears = 150, ring = 150 } :: { [string]: number },
	ATTACK_EVERY_BY_ZONE = { 0, 3.0, 2.6, 2.2, 1.8 }, -- seconds between casts
	ATTACK_RAMP = 0.03, -- level gained per second of chase
	ATTACK_MAX_LEVEL = 0.8,
	ATTACK_CAST_RANGE = 150,
	ATTACK_MAX_LEAD = 300, -- studs of path prediction (carriers run up to ~180 studs/s)

	-- After knocking an egg out, chasers circle it (escorting a hauler too).
	-- Whoever grabs it back is chased at once; otherwise they give up.
	REGROUP_SECONDS = 25,
	REGROUP_RADIUS = 10,
	REGROUP_SPEED = 26,
	RESUME_GRACE = 0.8, -- seconds before a resumed chaser may attack

	-- Reclaim: a dropped egg left alone this long is fetched by a drone and
	-- flown back to its zone (slowly, so it can be snatched back on the way).
	RECLAIM_DELAY = 5,
	RECLAIM_SEARCH_RADIUS = 150, -- idle guards this close answer; else one flies in
	RECLAIM_FLY_SPEED = 30,
	RECLAIM_CARRY_SPEED = 16,
	RECLAIM_REST_SECONDS = 180, -- lifetime of the egg once it is back
	-- Haulers fly over canyon walls: look this far ahead, keep this clearance.
	FLY_LOOKAHEAD = 16,
	FLY_CLEARANCE = 4,
	CLIMB_SPEED = 24,
	DESCEND_SPEED = 10,

	-- Void Hound: from this zone, the guard that starts a chase tears open a
	-- portal and a hound leaps out to chase on foot.
	HOUND_ENABLED = false, -- reserve deep-zone creature design for a later feature
	HOUND_FROM_ZONE = 4,
	HOUND_FACTOR = 0.8,
	PORTAL_SECONDS = 0.7,
	-- Idle guards with no player this close skip their patrol updates.
	GUARD_ACTIVE_RADIUS = 300,
	MAX_ACTIVE = 160, -- two guards per egg + orphans + shower guards + chasers
}

return deepFreeze(config)
