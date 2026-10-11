--!strict
-- Profile schema migrations. Each step is a pure function vN -> vN+1 that
-- mutates and returns the data table. Never edit a shipped step; add a new one.

local Migrations = {}

Migrations.LATEST = 1

-- [from] = step producing from + 1
local STEPS: { [number]: (data: { [string]: any }) -> { [string]: any } } = {
	-- [1] = function(data) data.newField = default; data.schema = 2; return data end,
}

-- Brings `data` up to LATEST. Returns the data and whether anything changed.
-- Errors on unknown future schemas so we never overwrite newer data.
function Migrations.run(data: { [string]: any }): ({ [string]: any }, boolean)
	local schema = tonumber(data.schema) or 1
	if schema > Migrations.LATEST then
		error(`profile schema {schema} is newer than server ({Migrations.LATEST})`)
	end
	local changed = false
	while schema < Migrations.LATEST do
		local step = STEPS[schema]
		assert(step, `missing migration step from schema {schema}`)
		data = step(data)
		schema += 1
		data.schema = schema
		changed = true
	end
	return data, changed
end

return Migrations
