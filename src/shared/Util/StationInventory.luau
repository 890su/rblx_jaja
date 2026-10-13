--!strict
-- Compare the exact item shown to the player before applying an exchange.
-- Hatch completion changes its view, never its identity.
local Types = require(script.Parent.Parent.Types)

local StationInventory = {}

function StationInventory.key(state: Types.PedestalState?): string
	if not state then
		return ""
	end
	return `{state.id or ""}|{state.creatureId}|{state.rarity}|{state.mutation or ""}|{state.hatchAt or 0}`
end

function StationInventory.exchange(
	profile: Types.PlayerProfile,
	slot: number,
	index: number,
	expectedSlot: string,
	expectedStored: string,
	capacity: number
): boolean
	if
		slot % 1 ~= 0
		or slot < 1
		or slot > capacity
		or index % 1 ~= 0
		or index < 1
		or index > #profile.storage
	then
		return false
	end
	local key = tostring(slot)
	local old, incoming = profile.pedestals[key], profile.storage[index]
	if
		StationInventory.key(old) ~= expectedSlot
		or StationInventory.key(incoming) ~= expectedStored
	then
		return false
	end
	profile.pedestals[key] = incoming
	if old then
		profile.storage[index] = old
	else
		table.remove(profile.storage, index)
	end
	return true
end

return table.freeze(StationInventory)
