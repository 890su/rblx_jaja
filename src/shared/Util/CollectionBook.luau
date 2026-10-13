--!strict
local Types = require(script.Parent.Parent.Types)
local Creatures = require(script.Parent.Parent.Config.Creatures)
local CollectionBook = {}
function CollectionBook.discover(profile: Types.PlayerProfile, now: number): (boolean, { string })
	local changed = false
	local found: { string } = {}
	local function scan(collection: { [any]: Types.PedestalState })
		for _, state in collection do
			if
				Creatures.BY_ID[state.creatureId]
				and (not state.hatchAt or state.hatchAt <= now)
				and not profile.index[state.creatureId]
			then
				profile.index[state.creatureId] = true
				table.insert(found, state.creatureId)
				changed = true
			end
		end
	end
	scan(profile.pedestals)
	scan(profile.storage)
	return changed, found
end
return CollectionBook
