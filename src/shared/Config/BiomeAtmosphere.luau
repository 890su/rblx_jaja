--!strict
local deepFreeze = require(script.Parent.Parent.Util.deepFreeze)
return deepFreeze({
	UPDATE_PERIOD = 0.2,
	TRANSITION_SECONDS = 0.9,
	BOUNDARY_HYSTERESIS = 8,
	EFFECT_DISTANCE = 420,
	PULSE_SECONDS = 3.5,
	PULSE_TRANSPARENCY = 0.26,
	PARTICLE_RATE = 3,
	MAX_EMITTERS = 4,
	PARTICLE_LIFETIME = 4,
})
