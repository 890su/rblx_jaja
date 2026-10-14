--!strict
-- Profile schema migrations. Each step is a pure function vN -> vN+1 that
-- mutates and returns the data table. Never edit a shipped step; add a new one.

local Migrations = {}

Migrations.LATEST = 4

-- [from] = step producing from + 1
local STEPS: { [number]: (data: { [string]: any }) -> { [string]: any } } = {
	[3] = function(data)
		-- Previously both facilities were free. Keep them and every upgrade;
		-- new v4 profiles start without either facility.
		data.treadmill = math.clamp(tonumber(data.treadmill) or 0, 0, 10) + 1
		data.flags = data.flags or {}
		data.flags.warehouseOwned = true
		return data
	end,
	[2] = function(data)
		data.treadmill = 0
		data.carryTraining = 0
		data.hatchCredits = 0
		data.restockCredits = 0
		return data
	end,
	[1] = function(data)
		data.uncollectedCoins = data.uncollectedCoins or 0
		data.serverLuckUntil = data.serverLuckUntil or 0
		data.outgoingTransfers = data.outgoingTransfers or {}
		data.incomingTransfers = data.incomingTransfers or {}
		-- Historical profiles did not track paid provenance; conservatively protect them.
		for _, collection in { data.pedestals or {}, data.storage or {} } do
			for _, state in collection do
				if state.paid == nil then
					state.paid = true
				end
			end
		end
		return data
	end,
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
