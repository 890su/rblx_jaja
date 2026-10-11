--!strict
-- Meteors on the track (GDD §4.2–4.3): server-timed spawning per zone with
-- server-rolled rarity, pickup via ProximityPrompt, carrying (slowed), drop on
-- death, and auto-placing on a pedestal when the carrier enters their station.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Zones = require(Shared.Config.Zones)
local Rarity = require(Shared.Config.Rarity)
local Theme = require(Shared.Theme)
local Odds = require(Shared.Util.Odds)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local WorldService = require(script.Parent.WorldService)
local StationService = require(script.Parent.StationService)
local SpeedService = require(script.Parent.SpeedService)

local PICKUP_DISTANCE = 14 -- server check; prompt range is 10
local DROPPED_LIFETIME = 10
local CARRY_CHECK_PERIOD = 0.2

export type Carry = { rarity: Types.Rarity, mutation: string?, visual: BasePart }

local MeteorService = {}

local rng = Random.new()
local alive: { [number]: number } = {} -- zone index -> live meteor count
local carrying: { [Player]: Carry } = {}
local fullWarnedAt: { [Player]: number } = {}
local fieldFolder: Folder
local notify: RemoteEvent

local function oneInText(zoneIndex: number, rarity: Types.Rarity): string
	local zone = Zones.ZONES[zoneIndex]
	local oneIn = zone and Odds.oneIn(zone.weights, rarity)
	return if oneIn and oneIn > 1 then ` · 1 in {oneIn}` else ""
end

local function makeMeteorPart(rarity: Types.Rarity): Part
	local meteor = Instance.new("Part")
	meteor.Name = `{rarity}Meteor`
	meteor.Shape = Enum.PartType.Ball
	meteor.Size = Vector3.new(3, 3, 3)
	meteor.Material = Enum.Material.Neon
	meteor.Color = Theme.RARITY_COLORS[rarity]
	meteor.CanCollide = false
	meteor:SetAttribute("Rarity", rarity)
	return meteor
end

local function rollMutation(): string?
	if rng:NextNumber() < Rarity.MUTATIONS.Golden.chance then
		return "Golden"
	end
	return nil
end

local spawnMeteor: (zoneIndex: number, position: Vector3, rarity: Types.Rarity, lifetime: number?) -> ()

local function pickUp(player: Player, meteor: Part, zoneIndex: number, isDropped: boolean)
	if carrying[player] or meteor:GetAttribute("Taken") then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	if (root.Position - meteor.Position).Magnitude > PICKUP_DISTANCE then
		return
	end
	local profile = DataService.get(player)
	if not profile then
		return
	end

	local rarity = meteor:GetAttribute("Rarity") :: Types.Rarity
	-- FTUE: first pickup in the guarantee zone is at least the guaranteed rarity.
	local guarantee = Zones.FIRST_VISIT_GUARANTEE
	if zoneIndex == guarantee.zone and not isDropped and not profile.flags.ftueRareGranted then
		profile.flags.ftueRareGranted = true
		if Rarity.INFO[rarity].order < Rarity.INFO[guarantee.rarity].order then
			rarity = guarantee.rarity
		end
	end

	meteor:SetAttribute("Taken", true)
	if not isDropped then
		alive[zoneIndex] = math.max(0, (alive[zoneIndex] or 1) - 1)
	end
	meteor:Destroy()

	local visual = makeMeteorPart(rarity)
	visual.Massless = true
	visual.Anchored = false
	visual.CFrame = root.CFrame * CFrame.new(0, 4.5, 0)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = visual
	weld.Part1 = root
	weld.Parent = visual
	visual.Parent = character

	carrying[player] = { rarity = rarity, mutation = rollMutation(), visual = visual }
	player:SetAttribute("Carrying", rarity)
	SpeedService.apply(player)
	notify:FireClient(
		player,
		`{rarity} {Theme.ITEM}{oneInText(zoneIndex, rarity)}! Bring it home`,
		"pickup"
	)
end

spawnMeteor = function(
	zoneIndex: number,
	position: Vector3,
	rarity: Types.Rarity,
	lifetime: number?
)
	local meteor = makeMeteorPart(rarity)
	meteor.Anchored = true
	meteor.Position = position

	local isDropped = lifetime ~= nil
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Grab"
	prompt.ObjectText = `{rarity} {Theme.ITEM}{oneInText(zoneIndex, rarity)}`
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = meteor
	prompt.Triggered:Connect(function(player)
		pickUp(player, meteor, zoneIndex, isDropped)
	end)

	meteor.Parent = fieldFolder
	if lifetime then
		task.delay(lifetime, function()
			if meteor.Parent then
				meteor:Destroy()
			end
		end)
	else
		alive[zoneIndex] = (alive[zoneIndex] or 0) + 1
	end
end

local function clearCarry(player: Player)
	local carry = carrying[player]
	if not carry then
		return
	end
	carrying[player] = nil
	if carry.visual.Parent then
		carry.visual:Destroy()
	end
	player:SetAttribute("Carrying", nil)
	SpeedService.apply(player)
end

local function dropCarry(player: Player, position: Vector3)
	local carry = carrying[player]
	if not carry then
		return
	end
	clearCarry(player)
	local zoneIndex = math.max(WorldService.zoneIndexAt(position), 1)
	spawnMeteor(zoneIndex, position, carry.rarity, DROPPED_LIFETIME)
end

local function checkDeliveries()
	for player, carry in carrying do
		local plot = StationService.getPlot(player)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if plot and root and WorldService.isInPlot(plot, root.Position) then
			if StationService.tryPlace(player, carry.rarity, carry.mutation) then
				clearCarry(player)
				notify:FireClient(
					player,
					`{carry.rarity} {Theme.ITEM} placed — hatching!`,
					"success"
				)
			elseif os.clock() - (fullWarnedAt[player] or 0) > 5 then
				fullWarnedAt[player] = os.clock()
				notify:FireClient(player, "All pedestals are full!", "warning")
			end
		end
	end
end

-- Exposed for the Steal system (week 3) and admin/testing tools.
function MeteorService.getCarry(player: Player): Carry?
	return carrying[player]
end

function MeteorService.init()
	notify = Remotes.event("Notify")
	fieldFolder = Instance.new("Folder")
	fieldFolder.Name = "Meteors"
	fieldFolder.Parent = workspace

	local function watchCharacter(player: Player, character: Model)
		local humanoid = character:WaitForChild("Humanoid") :: Humanoid
		humanoid.Died:Connect(function()
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				dropCarry(player, root.Position)
			else
				clearCarry(player)
			end
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
		clearCarry(player)
		fullWarnedAt[player] = nil
	end)
end

function MeteorService.start()
	for zoneIndex, zone in Zones.ZONES do
		task.spawn(function()
			while true do
				if (alive[zoneIndex] or 0) < zone.maxMeteors then
					local rarity = Odds.roll(zone.weights, Rarity.ORDER, rng)
					spawnMeteor(zoneIndex, WorldService.randomPointInZone(zoneIndex, rng), rarity)
				end
				task.wait(zone.spawnIntervalSeconds)
			end
		end)
	end
	while true do
		task.wait(CARRY_CHECK_PERIOD)
		checkDeliveries()
	end
end

return MeteorService
