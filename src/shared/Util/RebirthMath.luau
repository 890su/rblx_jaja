--!strict
-- Rebirth requirements (GDD §4.6), shared so the UI shows exactly what the
-- server checks.

local Economy = require(script.Parent.Parent.Config.Economy)

local RebirthMath = {}

-- Coins needed for the next rebirth when the player has `rebirths` already.
function RebirthMath.cost(rebirths: number): number
	return Economy.REBIRTH_BASE_COST * Economy.REBIRTH_COST_GROWTH ^ rebirths
end

function RebirthMath.speedRequired(rebirths: number): number
	return Economy.REBIRTH_SPEED_REQUIREMENT * (rebirths + 1)
end

return table.freeze(RebirthMath)
