--!strict
-- What a player is carrying (one item at a time): the visual above their head,
-- the slowdown, delivery to their own station, and what happens if the carry
-- is lost (death / leaving). Field meteors and stolen creatures both use this;
-- each carry decides its own onLost / onDelivered behaviour.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Theme = require(Shared.Theme)
local Creatures = require(Shared.Config.Creatures)
local Rarity = require(Shared.Config.Rarity)
local Format = require(Shared.Util.Format)
local Locale = require(Shared.Locale)

local Notifier = require(script.Parent.Parent.Util.Notifier)
local WorldService = require(script.Parent.WorldService)
local StationService = require(script.Parent.StationService)
local SpeedService = require(script.Parent.SpeedService)

local CHECK_PERIOD = 0.2
local FULL_WARN_COOLDOWN = 5

export type Carry = {
	state: Types.PedestalState, -- creature to place (hatchAt nil = start timer on placement)
	fresh: boolean, -- true for field meteors: hatch timer starts when placed
	onLost: (player: Player, carry: Carry, position: Vector3?) -> (),
	onDelivered: ((player: Player, carry: Carry) -> ())?,
	visual: BasePart?,
}

local CarryService = {}

local carrying: { [Player]: Carry } = {}
local fullWarnedAt: { [Player]: number } = {}

local function makeVisual(rarity: Types.Rarity): Part
	local part = Instance.new("Part")
	part.Name = "CarriedMeteor"
	part:SetAttribute("Rarity", rarity)
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(3, 3, 3)
	part.Material = Enum.Material.Neon
	part.Color = Theme.RARITY_COLORS[rarity]
	part.CanCollide = false
	part.CanQuery = false
	part.Massless = true
	return part
end

function CarryService.get(player: Player): Carry?
	return carrying[player]
end

-- Starts carrying. Returns false if the player already carries or has no body.
function CarryService.begin(player: Player, carry: Carry): boolean
	if carrying[player] then
		return false
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not root then
		return false
	end
	local visual = makeVisual(carry.state.rarity)
	visual.CFrame = root.CFrame * CFrame.new(0, 4.5, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = visual
	weld.Part1 = root
	weld.Parent = visual
	visual.Parent = character
	carry.visual = visual

	carrying[player] = carry
	player:SetAttribute("Carrying", carry.state.rarity)
	SpeedService.apply(player)
	return true
end

-- Ends the carry without side effects (caller decides what happens to it).
function CarryService.clear(player: Player): Carry?
	local carry = carrying[player]
	if not carry then
		return nil
	end
	carrying[player] = nil
	if carry.visual and carry.visual.Parent then
		carry.visual:Destroy()
	end
	player:SetAttribute("Carrying", nil)
	SpeedService.apply(player)
	return carry
end

local function lose(player: Player, position: Vector3?)
	local carry = CarryService.clear(player)
	if carry then
		carry.onLost(player, carry, position)
	end
end

local function checkDeliveries()
	for player, carry in carrying do
		local plot = StationService.getPlot(player)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if plot and root and WorldService.isInPlot(plot, root.Position) then
			local placed = if carry.fresh
				then StationService.placeNew(player, carry.state.creatureId, carry.state.mutation)
				else StationService.placeState(player, carry.state)
			if placed then
				CarryService.clear(player)
				if carry.onDelivered then
					carry.onDelivered(player, carry)
				end
			else
				-- Full: a better fresh meteor replaces the weakest creature.
				local replaced, value = nil, nil
				if carry.fresh then
					local creature = Creatures.BY_ID[carry.state.creatureId]
					replaced, value = StationService.replaceWeakest(player, {
						creatureId = carry.state.creatureId,
						rarity = carry.state.rarity,
						mutation = carry.state.mutation,
						hatchAt = os.time() + Rarity.INFO[creature.rarity].hatchSeconds,
					})
				end
				if replaced then
					CarryService.clear(player)
					Notifier.send(player, "creature_replaced", {
						old = Locale.ref(replaced),
						amount = Format.short(value :: number),
					}, "coins")
					if carry.onDelivered then
						carry.onDelivered(player, carry)
					end
				elseif os.clock() - (fullWarnedAt[player] or 0) > FULL_WARN_COOLDOWN then
					fullWarnedAt[player] = os.clock()
					Notifier.send(player, "pedestals_full", nil, "warning")
				end
			end
		end
	end
end

function CarryService.init()
	local function watchCharacter(player: Player, character: Model)
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		humanoid.Died:Connect(function()
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			lose(player, root and root.Position)
		end)
	end
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(character)
			watchCharacter(player, character)
		end)
		if player.Character then
			task.spawn(watchCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lose(player, nil)
		fullWarnedAt[player] = nil
	end)
end

function CarryService.start()
	while true do
		task.wait(CHECK_PERIOD)
		checkDeliveries()
	end
end

return CarryService
