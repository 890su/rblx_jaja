--!strict
local deepFreeze = require(script.Parent.Parent.Util.deepFreeze)

return deepFreeze({
	WAVE_DURATION = 2.8,
	FADE_SECONDS = 0.4,
	WAVE_CYCLES = 3,
	COOLDOWN_SECONDS = 3,
	MAX_HORIZONTAL_SPEED = 2,
	MAX_DRIFT = 0.7,
	SERVER_PERIOD = 0.1,
})
