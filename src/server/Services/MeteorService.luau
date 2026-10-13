--!strict
-- Meteors on the track (GDD §4.2–4.3): server-timed spawning per zone with
-- server-rolled rarity and pickup via ProximityPrompt. Carrying, delivery and
-- drop-on-death are handled by CarryService.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Types = require(Shared.Types)
local Zones = require(Shared.Config.Zones)
local Canyons = require(Shared.Config.Canyons)
local Rarity = require(Shared.Config.Rarity)
local Creatures = require(Shared.Config.Creatures)
local Theme = require(Shared.Theme)
local Odds = require(Shared.Util.Odds)
local Locale = require(Shared.Locale)

local Notifier = require(script.Parent.Parent.Util.Notifier)
local MeteorVisual = require(script.Parent.Parent.Util.MeteorVisual)
local DataService = require(script.Parent.DataService)
local WorldService = require(script.Parent.WorldService)
local CarryService = require(script.Parent.CarryService)
local SnatcherService = require(script.Parent.SnatcherService)
local TelemetryService = require(script.Parent.TelemetryService)
local SpeedService = require(script.Parent.SpeedService)

local PICKUP_DISTANCE = 14 -- server check; prompt range is 10
local DROPPED_LIFETIME = 60 -- time to read the loss message and recover the egg
local FIELD_LIFETIME = 180

local MeteorService = {}

local rng = Random.new()
local alive: { [number]: number } = {} -- zone index -> live meteor count
local fieldFolder: Folder

local function oneInText(zoneIndex: number, rarity: Types.Rarity, boost: number?): string
	local zone = Zones.ZONES[zoneIndex]
	local oneIn = zone and Odds.oneIn(zone.weights, rarity, boost)
	return if oneIn and oneIn > 1 and rarity ~= "Common" then ` · 1/{oneIn}` else ""
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
	boost: number?,
	droppedState: Types.PedestalState?,
	originZone: number?,
	restrictedOnly: boolean?
) -> Part

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
	local acceptedPosition = SpeedService.validatePosition(player)
	if not acceptedPosition or (acceptedPosition - meteor.Position).Magnitude > PICKUP_DISTANCE then
		return
	end
	local profile = DataService.get(player)
	if
		meteor:GetAttribute("Paid") == true
		and player:GetAttribute("PaidRandomItemsAllowed") ~= true
	then
		return
	end
	if not profile then
		return
	end
	if not SpeedService.isZoneUnlocked(player, zoneIndex) then
		return
	end

	local rarity = meteor:GetAttribute("Rarity") :: Types.Rarity
	local meteorBoost = meteor:GetAttribute("Boost") :: number?
	-- FTUE: first pickup in the guarantee zone is at least the guaranteed rarity.
	local guarantee = Zones.FIRST_VISIT_GUARANTEE
	if zoneIndex == guarantee.zone and not isDropped and not profile.flags.ftueRareGranted then
		if Rarity.INFO[rarity].order < Rarity.INFO[guarantee.rarity].order then
			rarity = guarantee.rarity
		end
	end

	-- Creature and mutation are decided at pickup (server RNG); the hatch only
	-- reveals them. The zone picks the creature pool.
	local droppedId = meteor:GetAttribute("DroppedCreatureId") :: string?
	local creature = if droppedId
		then Creatures.BY_ID[droppedId]
		else Creatures.pick(rarity, zoneIndex, rng)
	local began = CarryService.begin(player, {
		state = {
			creatureId = creature.id,
			paid = meteor:GetAttribute("Paid") == true,
			rarity = rarity,
			mutation = if isDropped
				then meteor:GetAttribute("DroppedMutation") :: string?
				else rollMutation(),
		},
		fresh = true,
		-- Dropped eggs remember where they came from, so re-grabbing one in
		-- zone 1 still counts as a deep-zone egg for the Void Run.
		originZone = (meteor:GetAttribute("OriginZone") :: number?) or zoneIndex,
		onLost = function(lostBy, carry, position)
			if position then
				local dropZone = math.max(WorldService.zoneIndexAt(position), 1)
				local dropped = spawnMeteor(
					dropZone,
					position,
					carry.state.rarity,
					DROPPED_LIFETIME,
					nil,
					carry.state,
					carry.originZone
				)
				-- After a beat a drone comes to fly the egg back to its zone.
				SnatcherService.reclaimLater(dropped, carry.originZone or dropZone, lostBy)
			end
		end,
		onDelivered = function(owner, carry)
			TelemetryService.funnel(owner, "FirstPlace")
			Notifier.send(
				owner,
				"meteor_placed",
				{ rarity = Locale.ref(carry.state.rarity) },
				"success"
			)
		end,
	})
	if not began then
		return
	end
	if zoneIndex == guarantee.zone and not isDropped then
		profile.flags.ftueRareGranted = true
	end
	meteor:SetAttribute("Taken", true)
	if meteor:GetAttribute("Counted") then
		alive[zoneIndex] = math.max(0, (alive[zoneIndex] or 1) - 1)
	end
	SnatcherService.onPickup(player, zoneIndex, rarity, meteor)
	meteor:Destroy()
	TelemetryService.funnel(player, "FirstPickup")
	Notifier.send(
		player,
		"meteor_pickup",
		{ rarity = Locale.ref(rarity), odds = oneInText(zoneIndex, rarity, meteorBoost) },
		"pickup"
	)
end

spawnMeteor = function(
	zoneIndex: number,
	position: Vector3,
	rarity: Types.Rarity,
	lifetime: number?,
	boost: number?,
	droppedState: Types.PedestalState?,
	originZone: number?,
	restrictedOnly: boolean?
): Part
	local meteor = makeMeteorPart(rarity)
	meteor.Anchored = true
	meteor.Position = position
	meteor:SetAttribute("Boost", boost)
	meteor:SetAttribute(
		"Paid",
		if droppedState
			then droppedState.paid == true
			else not restrictedOnly and MeteorService.luckBoost() > 1
	)
	meteor:SetAttribute("RestrictedOnly", restrictedOnly == true)
	meteor:SetAttribute("ZoneIndex", zoneIndex)
	meteor:SetAttribute("OriginZone", originZone or zoneIndex)
	MeteorVisual.attach(meteor, false)

	local isDropped = droppedState ~= nil
	meteor:SetAttribute("DroppedCreatureId", if droppedState then droppedState.creatureId else nil)
	meteor:SetAttribute("DroppedMutation", if droppedState then droppedState.mutation else nil)
	meteor:SetAttribute("Counted", lifetime == nil)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Grab"
	prompt.ObjectText = rarity -- localized term; odds shown as numbers below
	local odds = oneInText(zoneIndex, rarity, boost)
	if odds ~= "" then
		local oddsGui = Instance.new("BillboardGui")
		oddsGui.Name = "Odds"
		oddsGui.Size = UDim2.fromOffset(70, 22)
		oddsGui.StudsOffset = Vector3.new(0, 2.6, 0)
		oddsGui.MaxDistance = 60
		local oddsLabel = Instance.new("TextLabel")
		oddsLabel.Size = UDim2.fromScale(1, 1)
		oddsLabel.BackgroundTransparency = 1
		oddsLabel.TextScaled = true
		oddsLabel.Font = Enum.Font.FredokaOne
		oddsLabel.TextColor3 = Theme.RARITY_COLORS[rarity]
		oddsLabel.TextStrokeTransparency = 0.2
		oddsLabel.AutoLocalize = false
		oddsLabel.Text = odds:sub(#" · " + 1)
		oddsLabel.Parent = oddsGui
		oddsGui.Parent = meteor
	end
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = meteor
	prompt.Triggered:Connect(function(player)
		pickUp(player, meteor, zoneIndex, isDropped)
	end)

	meteor.Parent = fieldFolder
	CollectionService:AddTag(meteor, "FieldMeteor")
	if not isDropped then
		SnatcherService.guardMeteor(meteor, zoneIndex)
	end
	if not lifetime then
		alive[zoneIndex] = (alive[zoneIndex] or 0) + 1
	end
	-- Expiry is an attribute so a reclaiming drone can extend it.
	meteor:SetAttribute("ExpiresAt", os.clock() + (lifetime or FIELD_LIFETIME))
	task.spawn(function()
		while meteor.Parent do
			local expires = (meteor:GetAttribute("ExpiresAt") :: number?) or 0
			if os.clock() >= expires then
				if meteor:GetAttribute("Counted") then
					alive[zoneIndex] = math.max(0, (alive[zoneIndex] or 1) - 1)
				end
				meteor:Destroy()
				return
			end
			task.wait(math.clamp(expires - os.clock(), 0.1, 5))
		end
	end)
	return meteor
end

-- Server Luck product: multiplier on non-Common spawn weights while active.
function MeteorService.luckBoost(): number
	local untilTime = (workspace:GetAttribute("ServerLuckUntil") :: number?) or 0
	if untilTime > workspace:GetServerTimeNow() then
		return (workspace:GetAttribute("ServerLuckBoost") :: number?) or 1
	end
	return 1
end

local function needsFreeMeteors(): boolean
	for _, player in Players:GetPlayers() do
		if player:GetAttribute("PaidRandomItemsAllowed") ~= true then
			return true
		end
	end
	return false
end

-- Restricted accounts receive an independent, unboosted pool. They never
-- interact with the paid generator and do not pause another player's purchase.
local function spawnFreeAlternative(
	zoneIndex: number,
	position: Vector3,
	boost: number,
	lifetime: number?,
	random: Random
)
	if MeteorService.luckBoost() <= 1 or not needsFreeMeteors() then
		return
	end
	local rarity = Odds.roll(Zones.ZONES[zoneIndex].weights, Rarity.ORDER, random, boost)
	spawnMeteor(zoneIndex, position + Vector3.new(4, 0, 0), rarity, lifetime, boost, nil, nil, true)
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
	spawnMeteor(zoneIndex, position, rarity, lifetime, totalBoost, nil)
	spawnFreeAlternative(
		zoneIndex,
		position,
		boost * (if inCanyon then Canyons.RARITY_BOOST else 1),
		lifetime,
		eventRng
	)
end

function MeteorService.init()
	fieldFolder = Instance.new("Folder")
	fieldFolder.Name = "Meteors"
	fieldFolder.Parent = workspace
end

function MeteorService.start()
	workspace.World:GetAttributeChangedSignal("CanyonDay"):Connect(function()
		-- Remove pickups in the previous maze so none remain inside new walls.
		for _, meteor in fieldFolder:GetChildren() do
			local zoneIndex = meteor:GetAttribute("ZoneIndex") :: number?
			if zoneIndex and zoneIndex >= Canyons.FROM_ZONE then
				if meteor:GetAttribute("Counted") then
					alive[zoneIndex] = math.max(0, (alive[zoneIndex] or 1) - 1)
				end
				meteor:Destroy()
			end
		end
	end)
	for zoneIndex, zone in Zones.ZONES do
		task.spawn(function()
			while true do
				if (alive[zoneIndex] or 0) < zone.maxMeteors then
					local position, inCanyon = WorldService.randomPointInZone(zoneIndex, rng)
					if zoneIndex == 1 then
						-- Early pickups are visible from every station, before a long run.
						position = Vector3.new(position.X, position.Y, rng:NextNumber(-330, -160))
					end
					local boost = (if inCanyon then Canyons.RARITY_BOOST else 1)
						* MeteorService.luckBoost()
					local rarity = Odds.roll(zone.weights, Rarity.ORDER, rng, boost)
					spawnMeteor(zoneIndex, position, rarity, nil, boost, nil)
					spawnFreeAlternative(
						zoneIndex,
						position,
						if inCanyon then Canyons.RARITY_BOOST else 1,
						nil,
						rng
					)
				end
				task.wait(zone.spawnIntervalSeconds)
			end
		end)
	end
end

return MeteorService
