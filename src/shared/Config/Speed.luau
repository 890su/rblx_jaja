--!strict
-- Speed system tuning (GDD §4.1). Replicated: nothing secret, server never
-- trusts client-reported values.

local deepFreeze = require(script.Parent.Parent.Util.deepFreeze)

return deepFreeze({
	GAIN_PER_SECOND = 1, -- +Speed per second while moving
	TREADMILL_RATE_NO_PASS = 0.5, -- fraction of gain while on base treadmill
	MIN_MOVE_STUDS_PER_TICK = 2, -- position delta required to count as "running"

	-- WalkSpeed = BASE + COEFFICIENT * sqrt(Speed), capped
	BASE_WALKSPEED = 16,
	WALKSPEED_COEFFICIENT = 6,
	WALKSPEED_CAP = 400,
	-- High-speed contact must not turn a small curb/ramp into a launch pad.
	PHYSICS = {
		highSpeed = 80,
		maxSlopeAngle = 50,
		launchSlack = 10,
		maxClimbRiseSpeed = 20,
		probeHeight = 1.8,
		probeLift = 0.2,
		wallSkin = 0.4,
		maxStep = 0.1,
		brakeSeconds = 0.5,
		replicationGrace = 0.3,
	},

	CARRY_MULTIPLIER = 0.6, -- movement while carrying a meteor
	REBIRTH_GAIN_BONUS = 0.25, -- +25% gain per rebirth
	FRIEND_GAIN_BONUS = 0.10, -- per friend in server
	FRIEND_GAIN_BONUS_CAP = 0.30,
	PASS_MULTIPLIER = 2, -- 2x Speed game pass
})
