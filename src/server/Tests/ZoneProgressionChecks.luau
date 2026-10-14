--!strict
-- Runs inside the isolated commerce suite, using real spawn/pickup services.
local Shared = game.ReplicatedStorage.Shared
local Zones = require(Shared.Config.Zones)
local Rarity = require(Shared.Config.Rarity)
local Creatures = require(Shared.Config.Creatures)
local Income = require(script.Parent.Parent.Data.Income)
local Carry = require(script.Parent.Parent.Services.CarryService)
local Meteor = require(script.Parent.Parent.Services.MeteorService)
local Data = require(script.Parent.Parent.Services.DataService)
local Checks = {}

function Checks.run(player: Player, at: (Player, Vector3) -> (), check: (string, boolean) -> ())
	local profile = assert(Data.get(player), "progression profile")
	local oldRebirths, oldSpeed, oldGuarantee =
		profile.rebirths, profile.speed, profile.flags.ftueRareGranted
	profile.rebirths = 1
	Data.setSpeed(player, 9000)
	local folder = workspace:WaitForChild("Meteors")
	for index, zone in Zones.ZONES do
		local meteor: BasePart? = nil
		local deadline = os.clock() + 15
		repeat
			for _, item in folder:GetChildren() do
				if
					item:IsA("BasePart")
					and item:GetAttribute("ZoneIndex") == index
					and item:GetAttribute("Counted") == true
					and item:GetAttribute("Paid") ~= true
				then
					meteor = item
					break
				end
			end
			if not meteor then
				task.wait(0.1)
			end
		until meteor ~= nil or os.clock() >= deadline
		local target = assert(meteor, "missing natural zone meteor")
		local rarity = target:GetAttribute("Rarity") :: string
		check(`natural zone {index} respects loot table`, (zone.weights[rarity] or 0) > 0)
		at(player, target.Position + Vector3.new(0, 2, 5))
		-- Same authoritative handler as the prompt; synthetic holds do not
		-- reliably dispatch from background Studio test clients.
		Meteor.debugPickup(player, target)
		local carry = assert(Carry.get(player), `zone {index} pickup failed`)
		local species = assert(Creatures.BY_ID[carry.state.creatureId], "unknown species")
		check(
			`zone {index} pickup keeps tier and gated species`,
			species.rarity == carry.state.rarity
				and species.zone <= index
				and (zone.weights[carry.state.rarity] or 0) > 0
		)
		local minIncome = Rarity.INFO[Rarity.ORDER[index]].incomePerSecond
		check(`zone {index} carry has minimum income`, Income.ofPedestal(carry.state) >= minIncome)
		check(`zone {index} cargo remembers origin`, carry.originZone == index)
		Carry.clear(player)
	end
	for index = 3, #Zones.ZONES do
		Meteor.spawnEvent(index, 3, 60, Random.new(100 + index))
	end
	for _, item in folder:GetChildren() do
		if item:IsA("BasePart") then
			local index = item:GetAttribute("ZoneIndex") :: number
			local rarity = item:GetAttribute("Rarity") :: string
			check(
				"natural and shower spawns never fall below zone floor",
				(Zones.ZONES[index].weights[rarity] or 0) > 0
			)
		end
	end
	profile.rebirths, profile.flags.ftueRareGranted = oldRebirths, oldGuarantee
	Data.setSpeed(player, oldSpeed)
end

return Checks
