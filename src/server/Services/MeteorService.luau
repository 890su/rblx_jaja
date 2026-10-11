--!strict
-- Meteors on the track (GDD §4.2–4.3): server-timed spawning per zone with
-- server-rolled rarity and pickup via ProximityPrompt. Carrying, delivery and
-- drop-on-death are handled by CarryService.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Types = require(Shared.Types)
local Zones = require(Shared.Config.Zones)
local Canyons = require(Shared.Config.Canyons)
local Rarity = require(Shared.Config.Rarity)
local Creatures = require(Shared.Config.Creatures)
local Theme = require(Shared.Theme)
local Odds = require(Shared.Util.Odds)
local Remotes = require(Shared.Remotes)

local DataService = require(script.Parent.DataService)
local WorldService = require(script.Parent.WorldService)
local CarryService = require(script.Parent.CarryService)
local TelemetryService = require(script.Parent.TelemetryService)

local PICKUP_DISTANCE = 14 -- server check; prompt range is 10
local DROPPED_LIFETIME = 10

local MeteorService = {}

local rng = Random.new()
local alive: { [number]: number } = {} -- zone index -> live meteor count
local fieldFolder: Folder
local notify: RemoteEvent

local function oneInText(zoneIndex: number, rarity: Types.Rarity, boost: number?): string
	local zone = Zones.ZONES[zoneIndex]
	local oneIn = zone and Odds.oneIn(zone.weights, rarity, boost)
	return if oneIn and oneIn > 1 and rarity ~= "Common" then ` · 1 in {oneIn}` else ""
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

local spawnMeteor: (
	zoneIndex: number,
	position: Vector3,
	rarity: Types.Rarity,
	lifetime: number?,
	boost: number?
) -> ()

local function pickUp(player: Player, meteor: Part, zoneIndex: number, isDropped: boolean)
	if CarryService.get(player) or meteor:GetAttribute("Taken") then
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
	local meteorBoost = meteor:GetAttribute("Boost") :: number?
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

	-- Creature and mutation are decided at pickup (server RNG); the hatch only
	-- reveals them. The zone picks the creature pool.
	local creature = Creatures.pick(rarity, zoneIndex, rng)
	CarryService.begin(player, {
		state = { creatureId = creature.id, rarity = rarity, mutation = rollMutation() },
		fresh = true,
		onLost = function(_, carry, position)
			if position then
				local dropZone = math.max(WorldService.zoneIndexAt(position), 1)
				spawnMeteor(dropZone, position, carry.state.rarity, DROPPED_LIFETIME)
			end
		end,
		onDelivered = function(owner, carry)
			TelemetryService.funnel(owner, "FirstPlace")
			notify:FireClient(
				owner,
				`{carry.state.rarity} {Theme.ITEM} placed — hatching!`,
				"success"
			)
		end,
	})
	TelemetryService.funnel(player, "FirstPickup")
	notify:FireClient(
		player,
		`{rarity} {Theme.ITEM}{oneInText(zoneIndex, rarity, meteorBoost)}! Bring it home`,
		"pickup"
	)
end

spawnMeteor = function(
	zoneIndex: number,
	position: Vector3,
	rarity: Types.Rarity,
	lifetime: number?,
	boost: number?
)
	local meteor = makeMeteorPart(rarity)
	meteor.Anchored = true
	meteor.Position = position
	meteor:SetAttribute("Boost", boost)

	local isDropped = lifetime ~= nil
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Grab"
	prompt.ObjectText = `{rarity} {Theme.ITEM}{oneInText(zoneIndex, rarity, boost)}`
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

-- Server Luck product: multiplier on non-Common spawn weights while active.
function MeteorService.luckBoost(): number
	local untilTime = (workspace:GetAttribute("ServerLuckUntil") :: number?) or 0
	if untilTime > workspace:GetServerTimeNow() then
		return (workspace:GetAttribute("ServerLuckBoost") :: number?) or 1
	end
	return 1
end

-- Event meteor (Meteor Shower): boosted rarity, despawns after `lifetime`.
function MeteorService.spawnEvent(
	zoneIndex: number,
	boost: number,
	lifetime: number,
	eventRng: Random
)
	local zone = Zones.ZONES[zoneIndex]
	if not zone then
		return
	end
	local position, inCanyon = WorldService.randomPointInZone(zoneIndex, eventRng)
	local totalBoost = boost
		* (if inCanyon then Canyons.RARITY_BOOST else 1)
		* MeteorService.luckBoost()
	local rarity = Odds.roll(zone.weights, Rarity.ORDER, eventRng, totalBoost)
	spawnMeteor(zoneIndex, position, rarity, lifetime, totalBoost)
end

function MeteorService.init()
	notify = Remotes.event("Notify")
	fieldFolder = Instance.new("Folder")
	fieldFolder.Name = "Meteors"
	fieldFolder.Parent = workspace
end

function MeteorService.start()
	for zoneIndex, zone in Zones.ZONES do
		task.spawn(function()
			while true do
				if (alive[zoneIndex] or 0) < zone.maxMeteors then
					local position, inCanyon = WorldService.randomPointInZone(zoneIndex, rng)
					local boost = (if inCanyon then Canyons.RARITY_BOOST else 1)
						* MeteorService.luckBoost()
					local rarity = Odds.roll(zone.weights, Rarity.ORDER, rng, boost)
					spawnMeteor(zoneIndex, position, rarity, nil, boost)
				end
				task.wait(zone.spawnIntervalSeconds)
			end
		end)
	end
end

return MeteorService
