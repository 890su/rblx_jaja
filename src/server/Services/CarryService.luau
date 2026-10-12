--!strict
-- What a player is carrying (one item at a time): the visual held in their arms,
-- the slowdown, delivery to their own station, and what happens if the carry
-- is lost (death / leaving). Field meteors and stolen creatures both use this;
-- each carry decides its own onLost / onDelivered behaviour.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Theme = require(Shared.Theme)
local Creatures = require(Shared.Config.Creatures)
local Rarity = require(Shared.Config.Rarity)
local Income = require(script.Parent.Parent.Data.Income)

local Notifier = require(script.Parent.Parent.Util.Notifier)
local MeteorVisual = require(script.Parent.Parent.Util.MeteorVisual)
local WorldService = require(script.Parent.WorldService)
local StationService = require(script.Parent.StationService)
local SpeedService = require(script.Parent.SpeedService)

local CHECK_PERIOD = 0.2
local FULL_WARN_COOLDOWN = 5

export type Carry = {
	state: Types.PedestalState, -- creature to place (hatchAt nil = start timer on placement)
	fresh: boolean, -- true for field meteors: hatch timer starts when placed
	originZone: number?, -- zone the egg was first picked up in (Void Run trigger)
	owner: Player?, -- stolen creatures: the player it was taken from
	ownerSlot: string?,
	onLost: (player: Player, carry: Carry, position: Vector3?) -> (),
	onDelivered: ((player: Player, carry: Carry) -> ())?,
	visual: BasePart?,
}

local CarryService = {}

local carrying: { [Player]: Carry } = {}
local fullWarnedAt: { [Player]: number } = {}
local replacementHolds: { [Player]: { prompt: ProximityPrompt, at: number } } = {}

local function makeVisual(rarity: Types.Rarity): Part
	local part = Instance.new("Part")
	part.Name = "CarriedMeteor"
	part:SetAttribute("Rarity", rarity)
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(1.9, 2.25, 1.9)
	part.Material = Enum.Material.Neon
	part.Color = Theme.RARITY_COLORS[rarity]
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
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
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not root or not humanoid or humanoid.Health <= 0 then
		return false
	end
	local visual = makeVisual(carry.state.rarity)
	-- Held in front of the chest (CarryPoseController raises the arms).
	local torso = character:FindFirstChild("UpperTorso")
		or character:FindFirstChild("Torso")
		or root
	local holder = torso :: BasePart
	visual.CFrame = holder.CFrame * CFrame.new(0, -0.1, -1.55)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = visual
	weld.Part1 = holder
	weld.Parent = visual
	MeteorVisual.attach(visual, true, 0.7)
	visual.Parent = character
	carry.visual = visual

	carrying[player] = carry
	player:SetAttribute("Carrying", carry.state.rarity)
	player:SetAttribute("CarryIncome", Income.ofPedestal(carry.state))
	SpeedService.apply(player)
	return true
end

-- Players currently carrying a creature stolen from `owner`.
function CarryService.carriersOf(owner: Player): { Player }
	local list = {}
	for player, carry in carrying do
		if carry.owner == owner then
			table.insert(list, player)
		end
	end
	return list
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
	player:SetAttribute("CarryIncome", nil)
	SpeedService.apply(player)
	return carry
end

local function lose(player: Player, position: Vector3?)
	local carry = CarryService.clear(player)
	if carry then
		carry.onLost(player, carry, position)
	end
end

-- Knocks the carry out of the player's hands (e.g. a Void Snatcher hit).
function CarryService.drop(player: Player, position: Vector3)
	lose(player, position)
end

local function checkDeliveries()
	for player, carry in carrying do
		local plot = StationService.getPlot(player)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if
			plot
			and root
			and humanoid
			and humanoid.Health > 0
			and WorldService.isInPlot(plot, root.Position)
		then
			local placed = if carry.fresh
				then StationService.placeNew(player, carry.state.creatureId, carry.state.mutation)
				else StationService.placeState(player, carry.state)
			if placed then
				CarryService.clear(player)
				if carry.onDelivered then
					carry.onDelivered(player, carry)
				end
			else
				if os.clock() - (fullWarnedAt[player] or -math.huge) > FULL_WARN_COOLDOWN then
					fullWarnedAt[player] = os.clock()
					Notifier.send(player, "station_full_manual_hint", nil, "warning")
				end
			end
		end
	end
end

function CarryService.init()
	for _, plot in WorldService.getPlots() do
		for slot, pedestal in plot.pedestals do
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "ReplacePrompt"
			prompt.ActionText = "Replace (keep old in storage)"
			prompt.HoldDuration = 0.7
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.MaxActivationDistance = 10
			prompt.RequiresLineOfSight = false
			prompt.Enabled = false
			prompt.Parent = pedestal
			CollectionService:AddTag(prompt, "ReplacePrompt")
			prompt.PromptButtonHoldBegan:Connect(function(player)
				replacementHolds[player] = { prompt = prompt, at = os.clock() }
			end)
			prompt.PromptButtonHoldEnded:Connect(function(player)
				local held = replacementHolds[player]
				task.defer(function()
					if replacementHolds[player] == held then
						replacementHolds[player] = nil
					end
				end)
			end)
			prompt.Triggered:Connect(function(player)
				local carry = carrying[player]
				local held = replacementHolds[player]
				replacementHolds[player] = nil
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")
				if
					not carry
					or not held
					or held.prompt ~= prompt
					or os.clock() - held.at < 0.5
					or StationService.ownerOf(plot) ~= player
					or not root
					or not humanoid
					or humanoid.Health <= 0
					or (root.Position - pedestal.Position).Magnitude > 14
				then
					return
				end
				local state = table.clone(carry.state)
				if carry.fresh then
					state.hatchAt = os.time()
						+ Rarity.INFO[Creatures.BY_ID[state.creatureId].rarity].hatchSeconds
				end
				if StationService.replaceSlot(player, slot, state) then
					CarryService.clear(player)
					Notifier.send(player, "station_carry_replaced", nil, "success")
					if carry.onDelivered then
						carry.onDelivered(player, carry)
					end
				end
			end)
		end
	end
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
		replacementHolds[player] = nil
	end)
end

function CarryService.start()
	while true do
		task.wait(CHECK_PERIOD)
		checkDeliveries()
	end
end

return CarryService
