--!strict
-- Stations (bases): plot assignment, pedestals, hatch timers, server income
-- tick, the coin collector, overflow storage and creature visuals. All state
-- lives in the player's profile; the world objects are a view refreshed once
-- per tick. Game pass effects are read from server-set Player attributes
-- (Pass_<key>, written by MonetizationService).

local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Types = require(Shared.Types)
local Economy = require(Shared.Config.Economy)
local Speed = require(Shared.Config.Speed)
local Rarity = require(Shared.Config.Rarity)
local Creatures = require(Shared.Config.Creatures)
local Theme = require(Shared.Theme)
local Format = require(Shared.Util.Format)
local UpgradeMath = require(Shared.Util.UpgradeMath)
local Remotes = require(Shared.Remotes)

local Notifier = require(script.Parent.Parent.Util.Notifier)
local Income = require(script.Parent.Parent.Data.Income)
local DataService = require(script.Parent.DataService)
local WorldService = require(script.Parent.WorldService)
local SpeedService = require(script.Parent.SpeedService)
local TelemetryService = require(script.Parent.TelemetryService)
local RateLimit = require(script.Parent.Parent.Util.RateLimit)
local StationInventory = require(Shared.Util.StationInventory)
local CryoCapsuleBuild = require(script.Parent.Parent.Util.CryoCapsuleBuild)
local MeteorVisual = require(script.Parent.Parent.Util.MeteorVisual)

type Plot = WorldService.Plot

local StationService = {}

local plotOwner: { [number]: Player } = {}
local playerPlot: { [Player]: Plot } = {}
local lastIncomeAt: { [Player]: number } = {}
local collectDebounce: { [Player]: number } = {}
-- Auto-collect banks every tick; analytics gets one batched event per minute.
local autoBanked: { [Player]: number } = {}
local autoBankedFlushAt: { [Player]: number } = {}
local AUTO_BANK_LOG_PERIOD = 60

local fx: RemoteEvent
local inventoryRemote: RemoteEvent
local inventoryLimit = RateLimit.new(8, 3)

local isHatched = Income.isHatched
local incomeOf = Income.ofPedestal

local AURA_BRIGHTNESS: { [string]: number } = {
	Common = 0,
	Uncommon = 0.6,
	Rare = 1,
	Epic = 1.5,
	Legendary = 2.2,
	Mythic = 3,
}

local function hasPass(player: Player?, key: string): boolean
	return player ~= nil and player:GetAttribute(`Pass_{key}`) == true
end

-- Pass multipliers on income: 2x Coins and VIP.
function StationService.passIncomeMultiplier(player: Player): number
	local multiplier = 1
	if hasPass(player, "Coins2x") then
		multiplier *= Economy.COINS_PASS_MULTIPLIER
	end
	if hasPass(player, "VIP") then
		multiplier *= 1 + Economy.VIP_COIN_BONUS
	end
	return multiplier
end

-- Usable pedestals: coin-unlocked count + Station Expansion pass.
function StationService.capacity(player: Player, profile: Types.PlayerProfile): number
	local bonus = if hasPass(player, "Expansion") then Economy.PEDESTALS_EXPANSION_PASS else 0
	return profile.pedestalCount + bonus
end

function StationService.incomePerSecond(player: Player, profile: Types.PlayerProfile): number
	return Income.perSecond(profile, os.time(), StationService.passIncomeMultiplier(player))
end

-- Lower panel: creature name. Upper plate: income or hatch timer.
local function ensureView(pedestal: BasePart): (TextLabel, TextLabel, Part)
	local gui = assert(CryoCapsuleBuild.info(pedestal), "Capsule has no status panel")
	local value = assert(CryoCapsuleBuild.topValue(pedestal), "Capsule has no upper display")
	local orb = pedestal:FindFirstChild("Orb") :: Part?
	if not orb then
		local newOrb = Instance.new("Part")
		newOrb.Name = "Orb"
		newOrb.Shape = Enum.PartType.Ball
		newOrb.Size = Vector3.new(4, 4, 4)
		newOrb.Anchored = true
		newOrb.CanCollide = false
		newOrb.CanQuery = false
		newOrb.CanTouch = false
		newOrb.Material = Enum.Material.Neon
		newOrb.CFrame = pedestal.CFrame + Vector3.new(0, 3, 0)
		newOrb.Parent = pedestal
		orb = newOrb
	end
	return gui:FindFirstChild("Label") :: TextLabel, value, orb :: Part
end

-- Puts the creature's 3D model (ReplicatedStorage.Assets.Creatures.<id>) on the
-- pedestal, with a rarity aura. Returns false if no model exists (orb fallback).
local function showCreature(pedestal: BasePart, state: Types.PedestalState?): boolean
	local key = if state then `{state.creatureId}|{state.mutation or ""}` else ""
	if pedestal:GetAttribute("CreatureKey") == key then
		return pedestal:FindFirstChild("Creature") ~= nil
	end
	pedestal:SetAttribute("CreatureKey", key)
	local old = pedestal:FindFirstChild("Creature")
	if old then
		old:Destroy()
	end
	local light = pedestal:FindFirstChild("Aura") :: PointLight?
	if light then
		light:Destroy()
	end
	if not state then
		return false
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Creatures")
	local template = folder and folder:FindFirstChild(state.creatureId)
	if not template or not template:IsA("Model") then
		return false
	end
	local model = template:Clone()
	model.Name = "Creature"
	local box, size = model:GetBoundingBox()
	-- Fit the entire bounding box inside the circular chamber, including wings.
	local diameter = math.sqrt(size.X * size.X + size.Z * size.Z)
	local fit = math.min(1, 5.1 / math.max(0.01, diameter), 5.8 / math.max(0.01, size.Y))
	if fit < 1 then
		model:ScaleTo(model:GetScale() * fit)
		box, size = model:GetBoundingBox()
	end
	local floorOffset = (pedestal:GetAttribute("DisplayFloorOffset") :: number?) or 0.65
	local target = pedestal.Position + Vector3.new(0, floorOffset + size.Y / 2, 0)
	model:PivotTo(model:GetPivot() + (target - box.Position))
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
		end
	end
	if state.mutation == "Golden" then
		local highlight = Instance.new("Highlight")
		highlight.FillColor = Color3.fromRGB(255, 200, 40)
		highlight.FillTransparency = 0.55
		highlight.OutlineColor = Color3.fromRGB(255, 240, 150)
		highlight.Parent = model
	end
	model.Parent = pedestal
	local brightness = AURA_BRIGHTNESS[state.rarity] or 0
	if brightness > 0 then
		local aura = Instance.new("PointLight")
		aura.Name = "Aura"
		aura.Color = Theme.RARITY_COLORS[state.rarity]
		aura.Brightness = brightness
		aura.Range = 10
		aura.Parent = pedestal
	end
	return true
end

-- While an egg hatches, the capsule holds the meteor itself (same mesh as on
-- the field, rarity aura); FeedbackController spins it slowly. nil removes it.
local function showMeteor(pedestal: BasePart, rarity: Types.Rarity?)
	local key = rarity or ""
	if pedestal:GetAttribute("MeteorKey") == key then
		return
	end
	pedestal:SetAttribute("MeteorKey", key)
	local old = pedestal:FindFirstChild("HatchingMeteor")
	if old then
		old:Destroy()
	end
	if not rarity then
		return
	end
	local meteor = Instance.new("Part")
	meteor.Name = "HatchingMeteor"
	meteor.Shape = Enum.PartType.Ball
	meteor.Size = Vector3.new(2.6, 2.6, 2.6)
	meteor.Material = Enum.Material.Neon
	meteor.Color = Theme.RARITY_COLORS[rarity]
	meteor.Anchored, meteor.CanCollide, meteor.CanQuery, meteor.CanTouch = true, false, false, false
	local floorOffset = (pedestal:GetAttribute("DisplayFloorOffset") :: number?) or 0.65
	meteor.CFrame = CFrame.new(pedestal.Position + Vector3.new(0, floorOffset + 2.2, 0))
	MeteorVisual.attach(meteor, true, 0.85)
	local glow = Instance.new("PointLight")
	glow.Color, glow.Range, glow.Brightness = Theme.RARITY_COLORS[rarity], 9, 1.5
	glow.Parent = meteor
	meteor.Parent = pedestal
	CollectionService:AddTag(meteor, "HatchingMeteor")
end

local function refreshPlot(plot: Plot, profile: Types.PlayerProfile?)
	local now = os.time()
	local owner = plotOwner[plot.index]
	plot.model:SetAttribute("OwnerUserId", if owner then owner.UserId else nil)
	local capacity = if profile and owner then StationService.capacity(owner, profile) else 0
	if owner and profile then
		owner:SetAttribute("StorageCount", #profile.storage)
		owner:SetAttribute("StationCapacity", capacity)
		owner:SetAttribute("StationOccupied", StationService.creatureCount(profile))
	end
	local hasExpansion = hasPass(owner, "Expansion")
	local displayedMultiplier = if profile and owner
		then Income.multiplier(profile, StationService.passIncomeMultiplier(owner))
		else 1
	local nextCost = if profile and profile.pedestalCount < Economy.PEDESTALS_MAX_COINS
		then Economy.PEDESTAL_COSTS[profile.pedestalCount - Economy.PEDESTALS_START + 1]
		else nil
	for slot, pedestal in plot.pedestals do
		local label, value, orb = ensureView(pedestal)
		local state = profile and profile.pedestals[tostring(slot)]
		local unlocked = profile ~= nil and slot <= capacity
		pedestal:SetAttribute("Occupied", state ~= nil)
		pedestal:SetAttribute("PaidCreature", state ~= nil and state.paid == true)
		pedestal:SetAttribute("Rarity", if state then state.rarity else nil)
		pedestal:SetAttribute("Income", if state then incomeOf(state) else nil)
		pedestal:SetAttribute("Unlocked", unlocked)
		if not state or not isHatched(state, now) then
			pedestal:SetAttribute("IncomePulseAmount", nil)
			pedestal:SetAttribute("IncomePulseAt", nil)
			pedestal:SetAttribute("IncomePulseRarity", nil)
		end
		-- What a locked pedestal offers its owner (read by StationController).
		local isNextUnlock = profile ~= nil
			and not unlocked
			and nextCost ~= nil
			and slot == capacity + 1
		local isExpansionOffer = profile ~= nil
			and not unlocked
			and not hasExpansion
			and slot > Economy.PEDESTALS_MAX_COINS
		pedestal:SetAttribute("UnlockCost", if isNextUnlock then nextCost else nil)
		pedestal:SetAttribute("ExpansionOffer", isExpansionOffer or nil)
		local capsuleColor = if state
			then Theme.RARITY_COLORS[state.rarity]
			else Color3.fromRGB(95, 225, 255)
		local hatching = state ~= nil and not isHatched(state, now)
		local capsuleStatus = if not profile
			then "OFFLINE"
			elseif not unlocked then "Locked"
			elseif hatching then "Hatching"
			elseif state then "ACTIVE"
			else "Ready"
		local capsuleProgress = if hatching and state
			then 1 - ((state.hatchAt :: number) - now) / Rarity.INFO[state.rarity].hatchSeconds
			elseif state then 1
			else 0
		CryoCapsuleBuild.update(
			pedestal,
			unlocked,
			capsuleColor,
			capsuleStatus,
			hasPass(owner, "VIP"),
			capsuleProgress
		)
		if state then
			local color = Theme.RARITY_COLORS[state.rarity]
			label.TextColor3 = color
			if isHatched(state, now) then
				showMeteor(pedestal, nil)
				local hasModel = showCreature(pedestal, state)
				orb.Transparency = if hasModel then 1 else 0
				orb.Color = color
				orb.Size = Vector3.new(3.4, 3.4, 3.4)
				label.Text = Theme.CREATURE_NAMES[state.creatureId] or state.rarity
				value.Text = `+{Format.amount(incomeOf(state) * displayedMultiplier)}/s`
					.. (if state.mutation then " ★" else "")
			else
				showCreature(pedestal, nil)
				showMeteor(pedestal, state.rarity)
				orb.Transparency = 1
				label.Text = state.rarity
				value.Text = Format.duration((state.hatchAt :: number) - now)
			end
		else
			showCreature(pedestal, nil)
			showMeteor(pedestal, nil)
			orb.Transparency = 1
			label.TextColor3 = Color3.new(1, 1, 1)
			label.Text = if not profile then "" elseif unlocked then "Empty" else "Locked"
			value.Text = if isNextUnlock
				then `🔒 {Format.short(nextCost :: number)}`
				elseif isExpansionOffer then "🔒 R$"
				else ""
		end
	end
end

local function setOwnerSign(plot: Plot, player: Player?)
	local sign = plot.model:FindFirstChild("Sign")
	local label = sign and sign:FindFirstChild("Owner", true) :: TextLabel?
	if label then
		label.Text = if player then player.DisplayName else ""
	end
end

local function spawnAtPlot(player: Player, character: Model)
	local plot = playerPlot[player]
	if plot then
		SpeedService.markTeleport(player, plot.spawn.Position)
		character:PivotTo(plot.spawn)
	end
end

local function assignPlot(player: Player, profile: Types.PlayerProfile)
	for _, plot in WorldService.getPlots() do
		if not plotOwner[plot.index] then
			plotOwner[plot.index] = player
			playerPlot[player] = plot
			local offline = Income.offline(
				profile,
				os.time(),
				hasPass(player, "OfflinePlus"),
				StationService.passIncomeMultiplier(player)
			)
			profile.uncollectedCoins += offline
			lastIncomeAt[player] = os.time()
			profile.lastOnline = os.time()
			setOwnerSign(plot, player)
			refreshPlot(plot, profile)
			-- Player attributes always replicate (plot parts may be streamed out).
			player:SetAttribute("HomePosition", plot.center)
			player.CharacterAdded:Connect(function(character)
				task.defer(spawnAtPlot, player, character)
			end)
			if player.Character then
				spawnAtPlot(player, player.Character)
			end
			if offline > 0 then
				task.delay(3, function()
					Notifier.send(
						player,
						"welcome_back",
						{ amount = Format.short(offline) },
						"coins"
					)
				end)
			end
			return
		end
	end
	player:Kick("This server has no free station. Please join another server.")
end

local function releasePlot(player: Player)
	local plot = playerPlot[player]
	if not plot then
		return
	end
	plotOwner[plot.index] = nil
	playerPlot[player] = nil
	lastIncomeAt[player] = nil
	collectDebounce[player] = nil
	autoBanked[player] = nil
	autoBankedFlushAt[player] = nil
	setOwnerSign(plot, nil)
	refreshPlot(plot, nil)
end

local COLLECT_RADIUS = Vector3.new(7, 8, 5) -- half-extents around the collector pad
local COLLECT_CHECK_PERIOD = 0.2

local function bank(player: Player, plot: Plot, silent: boolean)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local amount = math.floor(profile.uncollectedCoins)
	if amount <= 0 then
		return
	end
	profile.uncollectedCoins -= amount
	DataService.addCoins(player, amount)
	if silent then
		autoBanked[player] = (autoBanked[player] or 0) + amount
		if os.clock() >= (autoBankedFlushAt[player] or 0) then
			TelemetryService.economy(player, "source", autoBanked[player], "Income", "auto")
			autoBanked[player] = 0
			autoBankedFlushAt[player] = os.clock() + AUTO_BANK_LOG_PERIOD
		end
	else
		TelemetryService.economy(player, "source", amount, "Income")
	end
	TelemetryService.funnel(player, "FirstCollect")
	if not silent then
		Notifier.send(player, "coins_collected", { amount = Format.short(amount) }, "coins")
		fx:FireClient(player, "collect", plot.collector.Position, amount)
	end
end

-- Server-side proximity instead of Touched: reliable for non-colliding pads
-- and can't be spoofed by firing touch events from the client.
local function tryCollect(player: Player, plot: Plot)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local position = SpeedService.validatePosition(player)
	if not root or not position then
		return
	end
	local offset = position - plot.collector.Position
	if
		math.abs(offset.X) > COLLECT_RADIUS.X
		or math.abs(offset.Y) > COLLECT_RADIUS.Y
		or math.abs(offset.Z) > COLLECT_RADIUS.Z
	then
		return
	end
	local now = os.clock()
	if (collectDebounce[player] or 0) > now then
		return
	end
	collectDebounce[player] = now + 1
	bank(player, plot, false)
end

function StationService.getPlot(player: Player): Plot?
	return playerPlot[player]
end

function StationService.ownerOf(plot: Plot): Player?
	return plotOwner[plot.index]
end

function StationService.creatureCount(profile: Types.PlayerProfile): number
	local count = 0
	for _ in profile.pedestals do
		count += 1
	end
	return count
end

function StationService.hasFreePedestal(player: Player): boolean
	local profile = DataService.get(player)
	if not profile then
		return false
	end
	for slot = 1, StationService.capacity(player, profile) do
		if not profile.pedestals[tostring(slot)] then
			return true
		end
	end
	return false
end

function StationService.refresh(player: Player)
	local plot = playerPlot[player]
	local profile = DataService.get(player)
	if plot and profile then
		refreshPlot(plot, profile)
	end
end

-- Puts an existing pedestal state (e.g. stolen or returned) on a free unlocked
-- pedestal, preferring `preferredSlot`. Keeps hatch timer and mutation.
function StationService.placeState(
	player: Player,
	state: Types.PedestalState,
	preferredSlot: string?
): boolean
	local profile = DataService.get(player)
	local plot = playerPlot[player]
	if not profile or not plot or not Creatures.BY_ID[state.creatureId] then
		return false
	end
	local capacity = StationService.capacity(player, profile)
	local key: string? = nil
	local preferredNumber = if preferredSlot then tonumber(preferredSlot) else nil
	if
		preferredSlot
		and not profile.pedestals[preferredSlot]
		and preferredNumber ~= nil
		and preferredNumber % 1 == 0
		and preferredNumber >= 1
		and preferredNumber <= capacity
	then
		key = preferredSlot
	else
		for slot = 1, capacity do
			if not profile.pedestals[tostring(slot)] then
				key = tostring(slot)
				break
			end
		end
	end
	if not key then
		return false
	end
	profile.pedestals[key] = table.clone(state)
	profile.pedestals[key].id = state.id or HttpService:GenerateGUID(false)
	refreshPlot(plot, profile)
	return true
end

-- Places a freshly picked-up meteor and starts its hatch timer.
function StationService.placeNew(player: Player, creatureId: string, mutation: string?): boolean
	local creature = Creatures.BY_ID[creatureId]
	if not creature then
		return false
	end
	return StationService.placeState(player, {
		creatureId = creatureId,
		paid = false,
		rarity = creature.rarity,
		mutation = mutation,
		hatchAt = os.time() + Rarity.INFO[creature.rarity].hatchSeconds,
	})
end

-- Gives a creature from a purchase/reward: on a free pedestal, else into
-- overflow storage (placed automatically when a pedestal frees up).
function StationService.give(
	player: Player,
	state: Types.PedestalState
): "placed" | "stored" | "failed"
	local profile = DataService.get(player)
	if not profile or not Creatures.BY_ID[state.creatureId] then
		return "failed"
	end
	if StationService.placeState(player, state) then
		return "placed"
	end
	local copy = table.clone(state)
	copy.id = copy.id or HttpService:GenerateGUID(false)
	table.insert(profile.storage, copy)
	StationService.refresh(player)
	return "stored"
end

-- Station full: swap the weakest creature for `state` if it earns more, selling
-- the old one for income * SELL_SECONDS. Returns (replacedName, coins) or nil.
function StationService.replaceWeakest(
	player: Player,
	state: Types.PedestalState
): (string?, number?)
	local profile = DataService.get(player)
	local plot = playerPlot[player]
	if not profile or not plot or not Creatures.BY_ID[state.creatureId] then
		return nil, nil
	end
	local weakestKey: string? = nil
	local weakestIncome = math.huge
	for slot = 1, StationService.capacity(player, profile) do
		local key = tostring(slot)
		local existing = profile.pedestals[key]
		if existing and incomeOf(existing) < weakestIncome then
			weakestKey, weakestIncome = key, incomeOf(existing)
		end
	end
	if not weakestKey or incomeOf(state) <= weakestIncome then
		return nil, nil
	end
	local old = profile.pedestals[weakestKey]
	local value = math.floor(weakestIncome * Economy.SELL_SECONDS)
	profile.pedestals[weakestKey] = table.clone(state)
	DataService.addCoins(player, value)
	TelemetryService.economy(player, "source", value, "Sell", old.creatureId)
	refreshPlot(plot, profile)
	return Theme.CREATURE_NAMES[old.creatureId] or old.rarity, value
end

-- Removes and returns the state on a pedestal (used by stealing).
function StationService.takeState(player: Player, slot: string): Types.PedestalState?
	local profile = DataService.get(player)
	local state = profile and profile.pedestals[slot]
	if not profile or not state then
		return nil
	end
	profile.pedestals[slot] = nil
	local plot = playerPlot[player]
	if plot then
		refreshPlot(plot, profile)
	end
	return state
end

-- Explicit carry replacement keeps the former occupant in storage.
function StationService.replaceSlot(
	player: Player,
	slot: number,
	state: Types.PedestalState
): boolean
	local profile = DataService.get(player)
	local plot = playerPlot[player]
	if
		not profile
		or not plot
		or not Creatures.BY_ID[state.creatureId]
		or slot % 1 ~= 0
		or slot < 1
		or slot > StationService.capacity(player, profile)
	then
		return false
	end
	local key = tostring(slot)
	local old = profile.pedestals[key]
	if not old then
		return false
	end
	profile.pedestals[key] = table.clone(state)
	profile.pedestals[key].id = state.id or HttpService:GenerateGUID(false)
	table.insert(profile.storage, old)
	refreshPlot(plot, profile)
	StationService.pushInventory(player)
	return true
end

function StationService.pushInventory(player: Player)
	local profile = DataService.get(player)
	if not profile then
		return
	end
	local function item(state: Types.PedestalState?): any
		return if state
			then {
				creatureId = state.creatureId,
				rarity = state.rarity,
				mutation = state.mutation,
				hatchAt = state.hatchAt,
				income = incomeOf(state),
				key = StationInventory.key(state),
			}
			else nil
	end
	local slots, storage = {}, {}
	for slot = 1, StationService.capacity(player, profile) do
		slots[tostring(slot)] = item(profile.pedestals[tostring(slot)])
	end
	for index, state in profile.storage do
		storage[index] = item(state)
	end
	inventoryRemote:FireClient(
		player,
		{ capacity = StationService.capacity(player, profile), slots = slots, storage = storage }
	)
end

local function inventoryAction(
	player: Player,
	action: unknown,
	slot: unknown,
	index: unknown,
	expectedSlot: unknown,
	expectedStored: unknown
)
	if not inventoryLimit:allow(player) then
		return
	end
	if action == "request" then
		StationService.pushInventory(player)
		return
	end
	local profile = DataService.get(player)
	local plot = playerPlot[player]
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not profile or not plot or not root or not humanoid or humanoid.Health <= 0 then
		return
	end
	local position = SpeedService.validatePosition(player)
	if not position or not WorldService.isInPlot(plot, position) then
		Notifier.send(player, "station_manage_home", nil, "warning")
		StationService.pushInventory(player)
		return
	end
	if
		typeof(slot) ~= "number"
		or slot % 1 ~= 0
		or slot < 1
		or slot > StationService.capacity(player, profile)
		or typeof(expectedSlot) ~= "string"
	then
		return
	end
	local key = tostring(slot)
	local state = profile.pedestals[key]
	local changed = false
	if action == "swap" and typeof(index) == "number" and typeof(expectedStored) == "string" then
		changed = StationInventory.exchange(
			profile,
			slot,
			index,
			expectedSlot,
			expectedStored,
			StationService.capacity(player, profile)
		)
		if changed then
			Notifier.send(player, "station_swapped", nil, "success")
		end
	elseif action == "sell" and state and StationInventory.key(state) == expectedSlot then
		local value = math.floor(incomeOf(state) * Economy.SELL_SECONDS)
		profile.pedestals[key] = nil
		DataService.addCoins(player, value)
		TelemetryService.economy(player, "source", value, "Sell", state.creatureId)
		Notifier.send(player, "station_sold", { amount = Format.short(value) }, "coins")
		changed = true
	end
	if changed then
		refreshPlot(plot, profile)
	else
		Notifier.send(player, "station_changed", nil, "warning")
	end
	StationService.pushInventory(player)
end

local function tickStation(player: Player, plot: Plot, profile: Types.PlayerProfile)
	-- Treadmill: AFK speed while standing on your own treadmill.
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		local offset = root.Position - plot.treadmill.Position
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local onTreadmill = humanoid ~= nil
			and humanoid.Health > 0
			and math.abs(offset.X) <= 4.5
			and math.abs(offset.Z) <= 7.5
			and offset.Y >= 0
			and offset.Y < 6
		if player:GetAttribute("OnTreadmill") ~= onTreadmill then
			player:SetAttribute("OnTreadmill", onTreadmill)
		end
		if onTreadmill then
			local gain = Speed.GAIN_PER_SECOND * UpgradeMath.treadmillRate(profile.treadmill)
			DataService.setSpeed(player, profile.speed + gain * SpeedService.gainMultiplier(player))
		end
	else
		player:SetAttribute("OnTreadmill", false)
	end

	-- Overflow storage drains onto free pedestals.
	while #profile.storage > 0 and StationService.placeState(player, profile.storage[1]) do
		table.remove(profile.storage, 1)
	end

	local now = os.time()
	local previous = lastIncomeAt[player] or now
	local elapsed = math.max(0, now - previous)
	lastIncomeAt[player] = now
	profile.lastOnline = now
	profile.playtimeTotal += elapsed
	local incomeMultiplier = Income.multiplier(profile, StationService.passIncomeMultiplier(player))
	local incomeThisTick = 0
	local pulseAt = workspace:GetServerTimeNow()
	local hatchingCount = 0
	for _, state in profile.storage do
		if not isHatched(state, now) then
			hatchingCount += 1
		end
	end
	for slot, state in profile.pedestals do
		if not isHatched(state, now) then
			hatchingCount += 1
		end
		if isHatched(state, now) then
			local amount = incomeOf(state)
				* incomeMultiplier
				* math.max(0, now - math.max(previous, state.hatchAt or previous))
			incomeThisTick += amount
			local pedestal = plot.pedestals[tonumber(slot) :: number]
			if pedestal then
				pedestal:SetAttribute("IncomePulseAmount", amount)
				pedestal:SetAttribute("IncomePulseRarity", state.rarity)
				pedestal:SetAttribute("IncomePulseAt", pulseAt)
			end
		end
		-- Hatch moment (crossed this tick): burst effect for everyone nearby.
		if
			state.hatchAt
			and now >= state.hatchAt
			and now - state.hatchAt < Economy.INCOME_TICK_SECONDS
		then
			local pedestal = plot.pedestals[tonumber(slot) :: number]
			if pedestal then
				fx:FireAllClients("hatch", pedestal.Position, state.rarity)
			end
			TelemetryService.funnel(player, "FirstHatch")
		end
	end
	-- The displayed per-capsule payouts and banked income are the same amounts.
	profile.uncollectedCoins += incomeThisTick
	if hasPass(player, "OfflinePlus") then
		bank(player, plot, true) -- Auto-collect
	end
	local stored = math.floor(profile.uncollectedCoins)
	local collectorGui = plot.collector:FindFirstChild("Info") :: BillboardGui?
	local collectorValue = collectorGui and collectorGui:FindFirstChild("Value") :: TextLabel?
	if collectorGui and collectorValue then
		collectorGui.Enabled = stored > 0
		collectorValue.Text = `+{Format.short(stored)}`
	end
	player:SetAttribute("StorageCount", #profile.storage)
	player:SetAttribute("HatchingCount", hatchingCount)
	refreshPlot(plot, profile)
end

function StationService.init()
	fx = Remotes.event("Fx")
	inventoryRemote = Remotes.event("StationState")
	Remotes.event("StationAction").OnServerEvent:Connect(inventoryAction)
	DataService.onLoaded(assignPlot)
	DataService.onRemoving(function(player, profile)
		-- Bank uncollected coins so leaving never loses income.
		local stored = math.floor(profile.uncollectedCoins)
		if stored > 0 then
			profile.coins += stored
			profile.uncollectedCoins -= stored
		end
		releasePlot(player)
	end)
	for _, plot in WorldService.getPlots() do
		refreshPlot(plot, nil)
	end
end

function StationService.start()
	task.spawn(function()
		while true do
			task.wait(COLLECT_CHECK_PERIOD)
			for player, plot in playerPlot do
				tryCollect(player, plot)
			end
		end
	end)
	while true do
		task.wait(Economy.INCOME_TICK_SECONDS)
		for player, plot in playerPlot do
			local profile = DataService.get(player)
			if profile then
				tickStation(player, plot, profile)
			end
		end
	end
end

return StationService
