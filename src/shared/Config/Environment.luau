--!strict
-- Only the release place may use the historical live datastore names.
-- Other published places (including DEV in the same experience) are isolated.
local deepFreeze = require(script.Parent.Parent.Util.deepFreeze)
local PRODUCTION_UNIVERSE_ID = 10770366757
local PRODUCTION_PLACE_ID = 105876478663615

local function storeName(base: string, studio: boolean, universeId: number, placeId: number): string
	if studio then
		return base .. "_dev"
	end
	if universeId == PRODUCTION_UNIVERSE_ID and placeId == PRODUCTION_PLACE_ID then
		return base
	end
	return `{base}_dev_{placeId}`
end

return deepFreeze({
	PRODUCTION_UNIVERSE_ID = PRODUCTION_UNIVERSE_ID,
	PRODUCTION_PLACE_ID = PRODUCTION_PLACE_ID,
	storeName = storeName,
})
