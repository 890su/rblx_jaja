--!strict
-- Global clock helpers. Shop restocks, Meteor Showers and crate rotations are
-- derived from synchronized server time so every server agrees on the same
-- cycle without coordination.

local Clock = {}

function Clock.now(): number
	return workspace:GetServerTimeNow()
end

-- Index of the current cycle of `period` seconds (shifted by `offset`).
function Clock.cycleIndex(period: number, offset: number?): number
	return math.floor((Clock.now() - (offset or 0)) / period)
end

-- Seconds until the next cycle boundary.
function Clock.timeUntilNext(period: number, offset: number?): number
	local t = Clock.now() - (offset or 0)
	return period - (t % period)
end

return table.freeze(Clock)
