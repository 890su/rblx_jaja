--!strict
-- Stealing, chase-back and protections (GDD §4.5). Enforced server-side only.

local deepFreeze = require(script.Parent.Parent.Util.deepFreeze)

return deepFreeze({
	PROMPT_HOLD_SECONDS = 1.5,
	MAX_STEAL_DISTANCE = 12,

	CHASE_SECONDS = 20,
	OWNER_CHASE_SPEED_BONUS = 0.5,
	CATCH_DISTANCE = 6,

	BASE_LOCK_SECONDS = 30,
	VIP_LOCK_BONUS_SECONDS = 10,
	SHIELD_PRODUCT_SECONDS = 15 * 60,

	NEW_PLAYER_PROTECTION_SECONDS = 10 * 60,
	PROTECTION_MIN_CREATURES = 3, -- Rebirth 0 players with fewer are protected
	THIEF_COOLDOWN_SECONDS = 60,
	SAME_VICTIM_COOLDOWN_SECONDS = 5 * 60,
	MYTHIC_MIN_VICTIM_CREATURES = 4,
})
